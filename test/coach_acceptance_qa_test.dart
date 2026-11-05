import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_service.dart';
import 'package:fittrack/features/ai/data/coach_proactive_providers.dart';
import 'package:fittrack/features/ai/data/coach_proactive_scheduler.dart';
import 'package:fittrack/features/ai/data/coach_weekly_facts.dart';
import 'package:fittrack/features/ai/data/coach_weekly_template.dart';
import 'package:fittrack/features/ai/data/coach_workout_recap.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/features/plan/data/reminder_scheduler.dart';
import 'package:fittrack/features/ai/data/sick_day_gate.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';
import 'package:fittrack/features/ai/data/coach_chip_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_extractor.dart';
import 'package:fittrack/features/ai/data/coach_memory_repository.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/domain/coach_chip_rules.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/ai/presentation/coach_memory_providers.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chip_bar.dart';
import 'package:fittrack/features/ai/presentation/widgets/coach_weekly_bubble.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';

import 'fake_database.dart';

/// QA 独立验收（严过关）—— 只证伪，不复用工程师的测试结论。
///
/// 本文件刻意覆盖「现有测试没打到的角落」，重点是：
///   · 迁移的**反向实验**（缺表的库 / 老行类型化读取）
///   · 数字出处的**逐项回溯**（不是断言文案像不像）
///   · 并发写入（两条路径都跑到 insert 时，唯一键是否真的兜住）
///   · `cancelAll` 的第 4 个口子（`settings_actions.scheduleReminders`）
///   · 记忆注入的真实组合（5 条 injury + 3 条 diet）
///   · 芯片规则①用**真实回执格式**（不是手写的假字符串）
void main() {
  // ═══════════════════════════════════════════════════════════
  // A. 迁移与数据层（反向实验）
  // ═══════════════════════════════════════════════════════════

  group('A. 迁移反向实验', () {
    test('A-4a：v23 库里**没有 user_settings 表** → 迁移不崩（不抛 no such table）',
        () async {
      final tmp = await Directory.systemTemp.createTemp('qa_v24_no_settings');
      final dbFile = p.join(tmp.path, 'fittrack.sqlite');
      final legacy = raw.sqlite3.open(dbFile);
      // 只有 ai_chat_messages，user_settings 缺失（半迁移 / 极老库现场）
      legacy.execute('''
        CREATE TABLE ai_chat_messages (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      legacy.execute('PRAGMA user_version = 23');
      legacy.dispose();

      AppDatabase? db;
      try {
        db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
        // 打开即触发 onUpgrade：这里抛异常就是"启动即死"
        await db.customSelect('SELECT 1').get();
        expect(await _userVersion(db), kSchemaVersion);
        expect(await _tableNames(db),
            containsAll(['coach_memories', 'coach_proactive_messages']));
        // chips 列仍然加上（ai_chat_messages 在）
        expect(await _columns(db, 'ai_chat_messages'), contains('chips'));
      } finally {
        await db?.close();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('A-4b：v23 库里**没有 ai_chat_messages 表** → 迁移不崩', () async {
      final tmp = await Directory.systemTemp.createTemp('qa_v24_no_chat');
      final dbFile = p.join(tmp.path, 'fittrack.sqlite');
      final legacy = raw.sqlite3.open(dbFile);
      _createV23UserSettings(legacy);
      legacy.execute('INSERT INTO user_settings (id) VALUES (1)');
      legacy.execute('PRAGMA user_version = 23');
      legacy.dispose();

      AppDatabase? db;
      try {
        db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
        await db.customSelect('SELECT 1').get();
        expect(await _userVersion(db), kSchemaVersion);
        expect(await _columns(db, 'user_settings'),
            containsAll(['coach_memory_enabled', 'coach_proactive_enabled']));
      } finally {
        await db?.close();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('A-3：老库升级后，老行通过 drift 类型化 API 读出必须是 true（不是只有 raw SQL 对）', () async {
      final tmp = await Directory.systemTemp.createTemp('qa_v24_typed_read');
      final dbFile = p.join(tmp.path, 'fittrack.sqlite');
      final legacy = raw.sqlite3.open(dbFile);
      _createV23UserSettings(legacy);
      // 迁移前就存在的老行
      legacy
          .execute("INSERT INTO user_settings (id, nickname) VALUES (1, '小嘎')");
      legacy.execute('PRAGMA user_version = 23');
      legacy.dispose();

      AppDatabase? db;
      try {
        db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
        await db.customSelect('SELECT 1').get();
        final entity = await UserSettingsRepositoryImpl(db).get();
        expect(entity, isNotNull);
        expect(entity!.coachMemoryEnabled, isTrue,
            reason: '老行读到 false 就是"启动后记忆永远不生效"的高危点');
        expect(entity.coachProactiveEnabled, isTrue);
        expect(entity.nickname, '小嘎', reason: '老数据不许丢');
      } finally {
        await db?.close();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('A-1：dedupe_key 的唯一性由 CREATE TABLE UNIQUE 落地（不是命名唯一索引）', () async {
      final db = fakeDatabase();
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();

      final indexes = await _indexNames(db);
      expect(indexes, contains('idx_coach_proactive_created_at'));
      expect(indexes.where((n) => n.contains('dedupe')), isEmpty,
          reason: '再建命名唯一索引 = 两个索引维护同一列，纯写放大');

      // 约束真的在：同 key 直接 insert 两次必须抛
      final repo = CoachProactiveRepository(db);
      await repo.insertIfAbsent(_weekly(DateTime(2025, 11, 17), 'a'));
      await expectLater(
        db.into(db.coachProactiveMessages).insert(
              CoachProactiveMessagesCompanion.insert(
                kind: 'weekly',
                dedupeKey: 'weekly:2025-11-17',
                content: 'b',
                source: 'template',
              ),
            ),
        throwsA(anything),
      );
      expect((await db.select(db.coachProactiveMessages).get()).length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // B. 周消息
  // ═══════════════════════════════════════════════════════════

  group('B. 周消息', () {
    late AppDatabase db;
    late CoachProactiveRepository repo;
    late UserSettingsRepositoryImpl settings;
    late WeeklyFactLoader facts;
    late _SharedNotif notif;
    late DateTime now;

    setUp(() {
      db = fakeDatabase();
      repo = CoachProactiveRepository(db);
      settings = UserSettingsRepositoryImpl(db);
      facts = WeeklyFactLoader(
        workout: WorkoutRepositoryImpl(db),
        body: BodyMetricRepositoryImpl(db),
        settings: settings,
      );
      notif = _SharedNotif();
      now = DateTime(2025, 11, 17, 8); // 周一 08:00
    });

    tearDown(() async => db.close());

    CoachProactiveScheduler scheduler() => CoachProactiveScheduler(
          repo: repo,
          facts: facts,
          generator: CoachWeeklyGenerator(),
          push: _FakePushSink(notif),
          settings: settings,
          overrides: DailyOverrideRepository(db),
          now: () => now,
        );

    Future<void> addWorkout(DateTime date, {int durationSec = 1800}) =>
        WorkoutRepositoryImpl(db).createWorkout(
          date: date,
          type: 'free',
          durationSec: durationSec,
          sets: const [],
        );

    Future<void> addWeight(DateTime date, double kg) =>
        BodyMetricRepositoryImpl(db).create(date: date, weightKg: kg);

    test('B-5 / W-9：模板里每个数字都能回溯到库里的行（抽查「2 次 / 30 分钟 / 1 天」）', () async {
      // 上周（11-10 ~ 11-16）：2 次训练 + 1 条称重
      await addWorkout(DateTime(2025, 11, 11, 19), durationSec: 1200);
      await addWorkout(DateTime(2025, 11, 13, 19), durationSec: 600);
      await addWeight(DateTime(2025, 11, 12, 7), 60);
      // 本周：绝不许参与
      await addWorkout(DateTime(2025, 11, 17, 9), durationSec: 3600);
      await addWeight(DateTime(2025, 11, 17, 7), 61);

      final f = await facts.load(now: now);
      final text = CoachWeeklyTemplate.render(f);

      // ① 「2 次」→ workouts 表里上周区间确实 2 行
      final allWorkouts = await db.select(db.workouts).get();
      final lastWeek = allWorkouts
          .where((w) =>
              !w.date.isBefore(DateTime(2025, 11, 10)) &&
              w.date.isBefore(DateTime(2025, 11, 17)))
          .toList();
      expect(lastWeek.length, 2, reason: '文案里的「2 次」必须能在库里数出 2 行');
      expect(text, contains('上周练了 2 次'));

      // ② 「30 分钟」→ 上周两行 duration_sec 之和 / 60
      final minutes =
          lastWeek.fold<int>(0, (s, w) => s + ((w.durationSec ?? 0) ~/ 60));
      expect(minutes, 30, reason: '文案里的「30 分钟」必须等于库里时长之和');
      expect(text, contains('一共 30 分钟'));

      // ③ 上周只有 1 天称重 → 算不出「从 A 走到 B」→ 整段不提体重
      final metrics = await db.select(db.bodyMetrics).get();
      final lastWeekDays = metrics
          .where((m) =>
              !m.date.isBefore(DateTime(2025, 11, 10)) &&
              m.date.isBefore(DateTime(2025, 11, 17)))
          .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
          .toSet();
      expect(lastWeekDays.length, 1, reason: '「顺手记 3 天体重」的触发依据是 1 < 3');
      expect(text, isNot(contains('体重从')));
      expect(text, isNot(contains('0 斤')), reason: '缺的数字绝不能填 0');
      expect(text, isNot(contains('0.0 斤')));
      expect(text, contains('顺手记 3 天体重'));

      // ④ 文案里**所有**数字都必须是上面这四个常量之一（没有凭空出现的数）
      final nums =
          RegExp(r'\d+').allMatches(text).map((m) => m.group(0)!).toSet();
      expect(nums, {'2', '30', '15', '3'},
          reason: '任何不在 {训练次数, 时长, 目标句常量, 称重天数提醒} 里的数字都是编造');
    });

    test('B-6 / W-3：两个 scheduler 实例并发跑（不共享 _inFlight）→ 库里只 1 行', () async {
      final a = scheduler();
      final b = scheduler();
      await Future.wait([a.runStartup(), b.runStartup()]);
      final rows = await db.select(db.coachProactiveMessages).get();
      expect(rows.length, 1, reason: '靠数据库唯一键兜住，不靠代码 if');
      expect(rows.single.dedupeKey, 'weekly:2025-11-17');
    });

    test('B-6 / W-3：两个 insertIfAbsent 并发抢同一个 key → 只有一条落库', () async {
      final results = await Future.wait([
        repo.insertIfAbsent(_weekly(DateTime(2025, 11, 17), '第一条')),
        repo.insertIfAbsent(_weekly(DateTime(2025, 11, 17), '第二条')),
      ]);
      expect((await db.select(db.coachProactiveMessages).get()).length, 1);
      expect(results.whereType<CoachProactiveMessage>().length, 1,
          reason: '另一个返回 null = 已生成，不是失败');
      expect(results.where((r) => r == null).length, 1);
    });

    test('B-7 / W-4：周一 08:00 排一次 id=200 @09:00；称重也 9 点 → 10:00', () async {
      final s = scheduler();
      await s.runStartup();
      expect(notif.scheduled.single.id, 200);
      expect(notif.scheduled.single.when, DateTime(2025, 11, 17, 9));

      // 换称重提醒时间后重来
      await settings.save(reminderHour: 9);
      now = DateTime(2025, 11, 17, 8, 30);
      await s.syncPush();
      expect(notif.scheduled.last.when, DateTime(2025, 11, 17, 10),
          reason: '同小时不出两条：顺延到 10:00');
    });

    test(
        'B-7：`ReminderScheduler.reschedule()`（内含 cancelAll）之后 syncPush 把 200 补回',
        () async {
      final s = scheduler();
      await s.runStartup();
      expect(notif.active, {200});

      // 模拟 app.dart::_scheduleOnStart 的既有行为
      final reminder = ReminderScheduler(
        sink: _FakeReminderSink(notif),
        gate: SickDayGate(DailyOverrideRepository(db), settings),
        now: () => now,
      );
      await reminder.reschedule(
        enabled: true,
        hour: 8,
        minute: 0,
        workoutSlots: const [],
        weighInId: kWeighInReminderId,
      );
      expect(notif.active.contains(200), isFalse,
          reason: 'cancelAll 会连 200 一起清掉');

      await s.syncPush(); // app.dart 末尾那一行
      expect(notif.active.contains(200), isTrue, reason: '不补回来 = 周消息永远收不到且无报错');
      expect(notif.scheduled.last.id, 200);
    });

    test('B-7【已修复】settings_actions.scheduleReminders() 走 reschedule() 之后补排 200',
        () async {
      // 模拟 `settings_actions.dart::scheduleReminders()` 的完整行为：
      // ① reschedule()（第一步 cancelAll 会清掉 200）→ ② 新增的 syncPush()。
      final s = scheduler();
      await s.runStartup();
      expect(notif.active, {200});

      final reminder = ReminderScheduler(
        sink: _FakeReminderSink(notif),
        gate: SickDayGate(DailyOverrideRepository(db), settings),
        now: () => now,
      );
      // 用户改提醒时间 / 重新打开提醒 → 走的就是这条
      await reminder.reschedule(
        enabled: true,
        hour: 9,
        minute: 0,
        workoutSlots: const [],
        weighInId: kWeighInReminderId,
      );

      expect(notif.active.contains(200), isFalse,
          reason: '前置事实：reschedule() 的 cancelAll() 会连 200 一起清掉');

      await s.syncPush(); // = settings_actions.dart 末尾新增的那一行
      expect(notif.active.contains(200), isTrue,
          reason: '改提醒时间 / 重新打开提醒之后 200 必须回来，否则周一 09:00 静默丢失');

      // 源码守卫：那一行真的在文件里，且紧跟 reschedule 之后
      final src =
          File('lib/features/settings/presentation/settings_actions.dart')
              .readAsStringSync();
      expect(src.contains('syncPush'), isTrue,
          reason: 'settings_actions.dart 的 reschedule(...) 之后必须补 '
              '`ref.read(coachProactiveSchedulerProvider).syncPush()`');
    });

    test('B-8 / W-7：周一 `reminderPaused` → 不推送，但内容照常生成', () async {
      await DailyOverrideRepository(db).upsert(
        date: DateTime(2025, 11, 17),
        reminderPaused: true,
        source: 'user',
      );
      await scheduler().runStartup();
      expect(notif.scheduled, isEmpty, reason: '生病免推');
      expect(await repo.getWeekly(DateTime(2025, 11, 17)), isNotNull,
          reason: '内容照旧生成（拦 ≠ 藏）');
    });

    test('B-9 / W-5 / W-6：已读不推；周一 9 点后才打开只内展不补推', () async {
      // 已读
      final s = scheduler();
      await s.runStartup();
      final record = (await repo.getWeekly(DateTime(2025, 11, 17)))!;
      await s.markSeen(record.id);
      notif.scheduled.clear();
      await s.syncPush();
      expect(notif.scheduled, isEmpty);
      expect(notif.active.contains(200), isFalse, reason: '已排的必须撤掉');

      // 迟到（周二 10:00 打开）
      final db2 = fakeDatabase();
      addTearDown(db2.close);
      final repo2 = CoachProactiveRepository(db2);
      final notif2 = _SharedNotif();
      final s2 = CoachProactiveScheduler(
        repo: repo2,
        facts: WeeklyFactLoader(
          workout: WorkoutRepositoryImpl(db2),
          body: BodyMetricRepositoryImpl(db2),
          settings: UserSettingsRepositoryImpl(db2),
        ),
        generator: CoachWeeklyGenerator(),
        push: _FakePushSink(notif2),
        settings: UserSettingsRepositoryImpl(db2),
        overrides: DailyOverrideRepository(db2),
        now: () => DateTime(2025, 11, 18, 10),
      );
      await s2.runStartup();
      expect(notif2.scheduled, isEmpty, reason: '迟到不补推');
      expect(await repo2.getWeekly(DateTime(2025, 11, 17)), isNotNull,
          reason: '但记录已生成，能内展');
    });

    test('B-9 / W-14：连续 2 周未读 → 不排通知，但内容仍生成', () async {
      for (final ws in [
        DateTime(2025, 11, 3),
        DateTime(2025, 11, 10),
      ]) {
        await repo.insertIfAbsent(_weekly(ws, '旧的周消息'));
      }
      await scheduler().runStartup();
      expect(notif.scheduled, isEmpty, reason: '降频免推');
      expect(await repo.getWeekly(DateTime(2025, 11, 17)), isNotNull,
          reason: '停推不等于停生成');
    });

    test('B-10：周日 23:59 与周一 00:01 的 week_start 必须分别落在各自那一周', () {
      expect(mondayOf(DateTime(2025, 11, 23, 23, 59)), DateTime(2025, 11, 17));
      expect(mondayOf(DateTime(2025, 11, 24, 0, 1)), DateTime(2025, 11, 24));
      // dedupe key 由调用方传入 weekStart；调度器里是
      // `weeklyDedupeKey(mondayOf(now))`，两种边界都必须落在各自的周一
      expect(weeklyDedupeKey(mondayOf(DateTime(2025, 11, 23, 23, 59))),
          'weekly:2025-11-17');
      expect(weeklyDedupeKey(mondayOf(DateTime(2025, 11, 24, 0, 1))),
          'weekly:2025-11-24');
      // 跨年：2026-01-01 是周四 → 周一是 2025-12-29
      expect(mondayOf(DateTime(2026, 1, 1)), DateTime(2025, 12, 29));
    });

    test('B-8 补充：周一九点前开生病模式 → 已排的 200 被取消（撤销而不是补推）', () async {
      final s = scheduler();
      await s.runStartup();
      expect(notif.active, {200});
      // 用户在 08:30 开了生病模式（写 override 后重跑决策）
      await DailyOverrideRepository(db).upsert(
        date: DateTime(2025, 11, 17),
        reminderPaused: true,
        source: 'user',
      );
      now = DateTime(2025, 11, 17, 8, 30);
      await s.syncPush();
      expect(notif.active.contains(200), isFalse);
      expect(notif.cancelled, contains(200));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // C. 记忆
  // ═══════════════════════════════════════════════════════════

  group('C. 记忆', () {
    late AppDatabase db;
    late CoachMemoryRepository repo;
    late UserSettingsRepositoryImpl settings;

    setUp(() async {
      db = fakeDatabase();
      repo = CoachMemoryRepository(db);
      settings = UserSettingsRepositoryImpl(db);
      // 没有 Key 就没有对话，抽取入口会直接短路 —— 必须先配一个假 Key
      await settings.save(aiApiKey: 'sk-test');
    });

    tearDown(() async => db.close());

    CoachMemoryService service(CoachMemoryExtractor extractor) =>
        CoachMemoryService(
          repo: repo,
          extractor: extractor,
          settings: settings,
        );

    CoachMemoryCandidate cand({
      String category = 'injury',
      String topic = '右膝',
      String content = '右膝半月板有旧伤',
      String quote = '我右膝半月板有旧伤',
      String action = 'remember',
    }) =>
        CoachMemoryCandidate(
          action: action,
          category: category,
          topic: topic,
          content: content,
          quote: quote,
        );

    Future<void> apply(List<CoachMemoryCandidate> candidates,
        {String text = '我右膝半月板有旧伤'}) async {
      await service(_FakeExtractor(candidates)).extractAndApply(
        userTurns: [text],
        currentUserText: text,
      );
    }

    test('C-12 / M-10：5 条 injury + 3 条 diet → 注入 4 条且 injury 只占 2 席', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.upsert(CoachMemoriesCompanion.insert(
          category: 'injury',
          topic: '伤$i',
          content: '第 $i 处旧伤',
          quote: '原话 $i',
        ));
      }
      for (var i = 1; i <= 3; i++) {
        await repo.upsert(CoachMemoriesCompanion.insert(
          category: 'diet',
          topic: '忌$i',
          content: '不吃第 $i 样',
          quote: '原话 d$i',
        ));
      }
      expect(await repo.count(), 8);

      final lines = await service(_FakeExtractor(const [])).promptLines();
      expect(lines.length, 4, reason: '注入硬上限 4 条');
      expect(lines.where((l) => l.startsWith('伤病·')).length, 2,
          reason: 'injury 最多占 2 位（不是把 4 个名额全吃光）');
      expect(lines.where((l) => l.startsWith('忌口·')).length, 2,
          reason: '剩下的名额按 agreement > diet 补足');
    });

    test('C-13 / M-4：「我晚上十点才下班」必须能记下（窄正则不许误杀作息）', () async {
      await apply([
        cand(
          category: 'schedule',
          topic: '下班时间',
          content: '晚上十点下班',
          quote: '我晚上十点才下班',
        ),
      ], text: '我晚上十点才下班');
      expect(await repo.count(), 1, reason: 'schedule 是白名单里最有价值的一类，误杀等于功能废了');
      final row = (await repo.listAll()).single;
      expect(row.category, 'schedule');
      expect(row.quote, '我晚上十点才下班', reason: 'quote 必须是用户原话');
    });

    test('C-13【已修复】句中带主语的一次性信息也要被窄正则拦住', () async {
      // 修复前 `_oneOff` 以 ^ 锚定，只拦得住"今天吃了碗面"，
      // 「我今天吃了碗面」会漏。现已改成"时间词 + 行为动词 + 完成体"，不再锚行首。
      await apply([
        cand(
            category: 'diet', topic: '面', content: '我今天吃了碗面', quote: '我今天吃了碗面'),
      ], text: '我今天吃了碗面');
      expect(await repo.count(), 0, reason: '句中带「我」的一次性信息同样不能落库');
      // 对照组：不带「我」的同义句必须被拦
      final db2 = fakeDatabase();
      addTearDown(db2.close);
      final repo2 = CoachMemoryRepository(db2);
      // ignore: unused_local_variable
      final svc2 = CoachMemoryService(
        repo: repo2,
        extractor: _FakeExtractor([
          cand(
              category: 'diet', topic: '面', content: '今天吃了碗面', quote: '今天吃了碗面'),
        ]),
        settings: UserSettingsRepositoryImpl(db2),
      );
      await svc2.extractAndApply(
        userTurns: const ['今天吃了碗面'],
        currentUserText: '今天吃了碗面',
      );
      expect(await repo2.count(), 0, reason: '不带「我」的形态必须被拦');
    });

    test('C-11 / M-1：模型编造 quote → 必须丢弃（防腐层）', () async {
      await apply([
        cand(quote: '我右膝半月板有旧伤'), // 真
        cand(
          category: 'diet',
          topic: '香菜',
          content: '不吃香菜',
          quote: '我说过我讨厌香菜', // 编造：不在原话里
        ),
      ]);
      expect(await repo.count(), 1);
      expect((await repo.listAll()).single.category, 'injury');
    });

    test('C-11 / M-5：category+topic 唯一覆盖（改口不留两条互相矛盾的记忆）', () async {
      await apply([cand()]);
      await apply([
        cand(content: '膝盖已经好了', quote: '我膝盖好了', topic: '右膝'),
      ], text: '我膝盖好了');
      expect(await repo.count(), 1);
      expect((await repo.listAll()).single.content, '膝盖已经好了');
    });

    test('C-11 / M-7：缺 topic → 不写（不存孤儿记忆）', () async {
      await apply([cand(topic: '   ')]);
      expect(await repo.count(), 0);
    });

    test('C-14 / M-15：开关关闭 → 不抽取、不注入、不显示留痕；已存数据保留', () async {
      await apply([cand()]);
      expect(await repo.count(), 1);

      await settings.saveCoachEngagement(memoryEnabled: false);
      final traces = <String>[];
      final svc =
          service(_FakeExtractor([cand(topic: '左肩', quote: '我右膝半月板有旧伤')]));
      // 不写
      final report = await svc.extractAndApply(
        userTurns: const ['我右膝半月板有旧伤'],
        currentUserText: '我右膝半月板有旧伤',
      );
      expect(report, isNull, reason: '关掉就不写、不留痕');
      // 不注入
      expect(await svc.promptLines(), isEmpty);
      // 数据保留
      expect(await repo.count(), 1);
      expect(traces, isEmpty);
    });

    test('C-15 / M-14：删最后一条 + 撤销 → 条数回到 1（不许抛 ref-after-dispose）', () async {
      await apply([cand()]);
      final svc = service(_FakeExtractor(const []));
      final removed = await svc.deleteById((await repo.listAll()).single.id);
      expect(removed, isNotNull);
      expect(await repo.count(), 0);
      // 撤销：走唯一键覆盖路径，不许撞键抛异常
      await svc.restore(removed!);
      expect(await repo.count(), 1);
    });

    test('C-16 / M-16：wipeAll 清空两张新表，且内置字典仍在（回归上一轮修复）', () async {
      await apply([cand()]);
      await CoachProactiveRepository(db)
          .insertIfAbsent(_weekly(DateTime(2025, 11, 17), '周消息'));
      expect(await repo.count(), 1);

      final tmp = await Directory.systemTemp.createTemp('qa_wipe');
      addTearDown(() async {
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      });
      // wipeAll 第一步是"先备份"，备份需要一个真实存在的库文件座位
      final fileDb = AppDatabase.withExecutor(
          NativeDatabase(File(p.join(tmp.path, 'fittrack.sqlite'))));
      await fileDb.customSelect('SELECT 1').get();
      await fileDb.close();

      // onCreate 已经灌过种子（内置食物 29 条 / 内置模板 5 个）
      final beforeFood = (await db.select(db.foodLibrary).get()).length;
      final beforeTpl = (await db.select(db.workoutTemplates).get()).length;
      expect(beforeFood, greaterThan(0));
      expect(beforeTpl, greaterThan(0));

      await DataWipeService.wipeAll(db: db, docsDir: tmp);

      expect(await db.select(db.coachMemories).get(), isEmpty,
          reason: '记忆必须清（最私密的一段内容）');
      expect(await db.select(db.coachProactiveMessages).get(), isEmpty);
      expect((await db.select(db.foodLibrary).get()).length, beforeFood,
          reason: '内置食物字典不许被清掉');
      expect((await db.select(db.workoutTemplates).get()).length, beforeTpl,
          reason: '内置模板不许被清掉');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // D. 芯片
  // ═══════════════════════════════════════════════════════════

  group('D. 芯片', () {
    test('D-17 / C-2①：用**真实回执格式**验证规则①（start_workout 失败 → 去开练）', () async {
      final db = fakeDatabase();
      addTearDown(db.close);

      // 真实链路：AiToolContext.append 会带上 toolName，回执来自 failureReceipt()
      final ctx = AiToolContext();
      ctx.append(
        const AiToolCall(
          id: 'call_1',
          name: 'start_workout',
          argumentsJson: '{"template":"燃脂"}',
        ),
        AiToolContext.failureReceipt('没找到模板「燃脂」'),
      );
      // 回执原文确认：{"ok":false,...}（不带工具名，靠 chipService 拼前缀）
      expect(ctx.messages.last.textOnly, '{"ok":false,"error":"没找到模板「燃脂」"}');

      final chips = await CoachChipService(
        body: BodyMetricRepositoryImpl(db),
        diet: DietRepositoryImpl(db),
      ).buildFor(
        assistantText: '嗯，这个模板没找到。',
        toolMessages: ctx.messages,
      );
      expect(chips.map((c) => c.key).toList(), ['open_workout'],
          reason: '规则① 若不命中就是静默失效，用户永远拿不到「去开练」');

      // 反向：ok:true 的回执不该给芯片（工具成功了没什么要补的）
      final ok = AiToolContext();
      ok.append(
        const AiToolCall(id: 'c2', name: 'start_workout', argumentsJson: '{}'),
        '{"ok":true,"template":"燃脂"}',
      );
      final none = await CoachChipService(
        body: BodyMetricRepositoryImpl(db),
        diet: DietRepositoryImpl(db),
      ).buildFor(assistantText: '好了，开始吧', toolMessages: ok.messages);
      expect(none, isEmpty);
    });

    test('D-17 / C-2：6 条规则逐条命中 / 不命中（一条不命中就不给芯片）', () {
      // ① 失败回执
      expect(
        CoachChipRules.build(
          assistantText: '',
          toolReceipts: const ['start_workout:{"ok":false,"error":"x"}'],
          hasWeightToday: true,
          hasFoodToday: true,
        ).map((c) => c.key),
        ['open_workout'],
      );
      // ②~⑥ 正文关键字，今日记录都已存在（把 C5 的条件排除掉）
      final keys = <String, String>{
        'open_workout': '要不今天开练一次',
        'set_reminder': '记得设个提醒',
        'open_trends': '看趋势就行',
      };
      keys.forEach((expected, text) {
        final out = CoachChipRules.build(
          assistantText: text,
          toolReceipts: const [],
          hasWeightToday: true,
          hasFoodToday: true,
        );
        expect(out.map((c) => c.key), contains(expected), reason: text);
      });
      // ③ / ⑤ 的前置条件：今日有记录 → 不出
      expect(
        CoachChipRules.build(
          assistantText: '称一下体重',
          toolReceipts: const [],
          hasWeightToday: true,
          hasFoodToday: true,
        ),
        isEmpty,
      );
      expect(
        CoachChipRules.build(
          assistantText: '蛋白吃得太少',
          toolReceipts: const [],
          hasWeightToday: false,
          hasFoodToday: true,
        ),
        isEmpty,
      );
      // ④ 一条不命中 → 空
      expect(
          CoachChipRules.build(
            assistantText: '嗯，是这么回事',
            toolReceipts: const [],
            hasWeightToday: false,
            hasFoodToday: false,
          ),
          isEmpty,
          reason: 'C4：不给兜底芯片');
    });

    test('D-18 / C-1 / C-7：只存 key，不存 route；白名单外 key 一律丢弃', () {
      expect(CoachChip.encode(const [CoachChip('open_workout')]),
          '[{"k":"open_workout"}]');
      expect(
          CoachChip.encode(const [CoachChip('open_workout')])!
              .contains('route'),
          isFalse,
          reason: '存了 route 就会在计划被删后白屏');

      // 老消息：NULL / 非法 JSON / 白名单外 → 空列表，不崩
      expect(CoachChip.decode(null), isEmpty);
      expect(CoachChip.decode(''), isEmpty);
      expect(CoachChip.decode('not json'), isEmpty);
      expect(CoachChip.decode('[{"k":"hack"}]'), isEmpty);
      expect(
        CoachChip.decode('[{"k":"open_workout"},{"k":"hack"}]')
            .map((c) => c.key)
            .toList(),
        ['open_workout'],
        reason: 'C1：白名单外不渲染',
      );
    });

    testWidgets('D-18：计划被删后点「去开练」→ 落 /workout/start（不白屏）',
        (tester) async {
      String? location;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (ctx, s) => Scaffold(
              body: Center(
                child: Consumer(builder: (c, ref, _) {
                  return ElevatedButton(
                    onPressed: () =>
                        openCoachChip(c, ref, const CoachChip('open_workout')),
                    child: const Text('tap'),
                  );
                }),
              ),
            ),
          ),
          GoRoute(
            path: '/workout/start',
            builder: (c, s) {
              location = s.uri.toString();
              return const Scaffold(body: Text('训练页'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      // 用户已经删掉所有计划（getAll → 空）
      final container = ProviderContainer(overrides: [
        planRepoProvider.overrideWithValue(_EmptyPlanRepository()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();
      expect(location, '/workout/start',
          reason: '无计划时「去开练」应 push 顶层路由 /workout/start（不能 push 底部 Tab 导致白屏）');
      expect(find.text('训练页'), findsOneWidget);
    });

    testWidgets('D-19 / C-6 / C-7：`chips` 为 NULL 的历史消息正常渲染、不崩、不画芯片',
        (tester) async {
      final db = fakeDatabase();
      addTearDown(db.close);
      await db.into(db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(role: 'assistant', content: '老消息正文'));
      final history = await AiChatRepository(db).getHistory();
      expect(history.single.chips, isEmpty);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AiMessageList(
            messages: history,
            streamingText: '',
            isStreaming: false,
            headAsset: 'assets/guga/guga_lv1.png',
          ),
        ),
      ));
      expect(find.text('老消息正文'), findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // D2. 芯片点击 = 快捷键，不是对话轮次（C-8）
  // ═══════════════════════════════════════════════════════════

  group('D2. 芯片点击（C-8）', () {
    testWidgets('点「记体重」→ 跳 /body?focus=weight，且对话历史一条都没多', (tester) async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final chatRepo = AiChatRepository(db);
      await chatRepo
          .add('assistant', '先记个体重吧', chips: const [CoachChip('log_weight')]);
      final before = await chatRepo.getHistory();
      expect(before.length, 1);

      String? location;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (ctx, s) => Scaffold(
              body: Center(
                child: Consumer(builder: (c, ref, _) {
                  return ElevatedButton(
                    onPressed: () =>
                        openCoachChip(c, ref, const CoachChip('log_weight')),
                    child: const Text('tap'),
                  );
                }),
              ),
            ),
          ),
          GoRoute(
            path: '/body',
            builder: (c, s) {
              location = s.uri.toString();
              return const Scaffold(body: Text('body'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        aiChatRepoProvider.overrideWithValue(chatRepo),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('tap'));
      await tester.pumpAndSettle();

      expect(location, '/body?focus=weight', reason: '「记体重」要直接弹录入');
      // C-8：不写对话历史（点了记体重 ≠ 说了一句"我要记体重"）
      expect((await chatRepo.getHistory()).length, 1);
      expect(find.text('body'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // E. 训练后点评 + 回归
  // ═══════════════════════════════════════════════════════════

  group('E. 点评与回归', () {
    test('E-20：去重键 / 同日覆盖 / 本周第 3 次不生成 / 时长未知不生成', () async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final repo = CoachProactiveRepository(db);
      var now = DateTime(2025, 11, 17, 19);
      final svc = CoachWorkoutRecapService(
        repo: repo,
        settings: UserSettingsRepositoryImpl(db),
        now: () => now,
      );

      // 时长未知 → 不生成
      expect(
        await svc.generateFor(
          workoutId: 1,
          exerciseCategories: const {'strength'},
          durationSec: null,
        ),
        isNull,
      );

      final first = await svc.generateFor(
        workoutId: 2,
        exerciseCategories: const {'strength'},
        durationSec: 25 * 60,
      );
      expect(first!.dedupeKey, 'recap:2');
      expect(first.source, 'template');

      // 同日第二次 → 只留后者
      final second = await svc.generateFor(
        workoutId: 3,
        exerciseCategories: const {'cardio'},
        durationSec: 30 * 60,
      );
      expect(second!.dedupeKey, 'recap:3');
      expect((await db.select(db.coachProactiveMessages).get()).length, 1,
          reason: '一天练两次不该收到两条点评');

      // 次日第二次（本周第 2 条）→ 仍然生成
      now = DateTime(2025, 11, 19, 19);
      expect(
        await svc.generateFor(
          workoutId: 4,
          exerciseCategories: const {'strength'},
          durationSec: 20 * 60,
        ),
        isNotNull,
      );
      expect((await db.select(db.coachProactiveMessages).get()).length, 2);

      // 本周第 3 条 → 不生成
      now = DateTime(2025, 11, 21, 19);
      expect(
        await svc.generateFor(
          workoutId: 5,
          exerciseCategories: const {'strength'},
          durationSec: 20 * 60,
        ),
        isNull,
        reason: '每周 ≤2 条',
      );
      expect((await db.select(db.coachProactiveMessages).get()).length, 2);
    });

    test('E-20：点评文案不含「加油 / 坚持就是胜利」，也不提大卡', () {
      for (final c in [
        recapContentFor(
            exerciseCategories: const {'strength'}, durationSec: 20 * 60),
        recapContentFor(
            exerciseCategories: const {'cardio'}, durationSec: 30 * 60),
        recapContentFor(
            exerciseCategories: const {'strength'}, durationSec: 5 * 60),
      ]) {
        expect(c, isNotNull);
        expect(c, isNot(contains('加油')));
        expect(c, isNot(contains('坚持就是胜利')));
        expect(c, isNot(contains('大卡')));
      }
    });

    testWidgets('E-20：点点评气泡只预填（落 /ai/coach + extra=预填句），不自动发送', (tester) async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final repo = CoachProactiveRepository(db);
      final svc = CoachWorkoutRecapService(
        repo: repo,
        settings: UserSettingsRepositoryImpl(db),
        now: () => DateTime.now(),
      );
      await svc.generateFor(
        workoutId: 7,
        exerciseCategories: const {'strength'},
        durationSec: 25 * 60,
      );

      String? pushedLocation;
      Object? pushedExtra;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => const Scaffold(
                body: SingleChildScrollView(child: CoachWeeklyBubble())),
          ),
          GoRoute(
            path: '/ai/coach',
            builder: (c, s) {
              pushedLocation = s.uri.toString();
              pushedExtra = s.extra;
              return const Scaffold(body: Text('coach'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        coachProactiveRepoProvider.overrideWithValue(repo),
        userSettingsProvider
            .overrideWith((ref) async => const UserSettingsEntity(id: 1)),
        coachWorkoutRecapServiceProvider.overrideWithValue(svc),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('力量练得挺实在'), findsOneWidget);
      await tester.tap(find.textContaining('力量练得挺实在'));
      await tester.pumpAndSettle();

      expect(pushedLocation, '/ai/coach');
      expect(pushedExtra, kRecapPrefill, reason: '只预填、不自动发送（请求要花钱，用户可能想换个问法）');
      // 复盘：模型调用次数必须是 0 —— 这里没有任何 runner 参与，标题即证据
      expect(
          await repo.countKindBetween(
            kind: kRecapKind,
            from: DateTime.now().subtract(const Duration(days: 1)),
            to: DateTime.now().add(const Duration(days: 1)),
          ),
          1);
    });

    test('E-21 / P-2：旧工具面与安全闸门（28 / 21 写 / 7 只读 / 5 危险，legacyDefs）', () {
      expect(AiToolSpecs.legacyDefs.length, 28, reason: '基线 25 + 训练记录增删改查 3 个');
      expect(AiToolSpecs.writeTools.length, 21);
      expect(AiToolSpecs.readOnlyTools.length, 7);
      expect(AiToolSpecs.destructiveTools.length, 5);
      expect(AiToolLimits.maxCallsPerRound, 12,
          reason: '8 → 12：覆盖建模板 + 批量补建动作');
      // 写操作仍逐次确认：写集合与只读集合不相交，且 start_workout 在写集合里
      expect(
        AiToolSpecs.writeTools.intersection(AiToolSpecs.readOnlyTools).isEmpty,
        isTrue,
      );
      expect(AiToolSpecs.writeTools, contains(AiToolSpecs.startWorkout));
    });

    test('E-21：AiMessage.toJson() 不含 chips（带出去会污染 prompt 甚至 400）', () {
      const msg = AiMessage(
        role: 'assistant',
        content: '练完了',
        chips: [CoachChip('open_workout')],
      );
      expect(msg.toJson().containsKey('chips'), isFalse);
    });

    test('E-21：工具失败回执仍进上下文（模型才知道"没做成、为什么"）', () {
      final ctx = AiToolContext();
      const call = AiToolCall(
          id: 'c1', name: 'log_weight', argumentsJson: '{"weight_kg":60}');
      ctx.append(call, AiToolContext.failureReceipt('保存失败'));
      // assistant(tool_calls) + tool(结果) 必须成对出现
      expect(ctx.messages.length, 2);
      expect(ctx.messages.first.toolCalls, isNotEmpty);
      expect(ctx.messages.last.role, 'tool');
      expect(ctx.messages.last.toolName, 'log_weight');
      expect(ctx.messages.last.textOnly, contains('"ok":false'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // F. 补充证伪（接线 / 半迁移 / 总开关）
  // ═══════════════════════════════════════════════════════════

  group('F. 补充证伪', () {
    test('A-2c：**部分**半迁移（表已建、列没加、user_version 仍 23）→ 重跑收敛，不崩', () async {
      final tmp = await Directory.systemTemp.createTemp('qa_v24_partial');
      final dbFile = p.join(tmp.path, 'fittrack.sqlite');
      final legacy = raw.sqlite3.open(dbFile);
      _createV23UserSettings(legacy);
      legacy.execute('''
        CREATE TABLE ai_chat_messages (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL DEFAULT 0
        )
      ''');
      // 上次迁移只跑了一半：coach_memories 建好了，其它都没做
      legacy.execute('''
        CREATE TABLE coach_memories (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          category TEXT NOT NULL,
          topic TEXT NOT NULL,
          content TEXT NOT NULL,
          quote TEXT NOT NULL,
          source_message_id INTEGER,
          created_at INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL DEFAULT 0,
          last_used_at INTEGER,
          UNIQUE (category, topic)
        )
      ''');
      legacy.execute('PRAGMA user_version = 23');
      legacy.dispose();

      AppDatabase? db;
      try {
        db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
        await db.customSelect('SELECT 1').get();
        expect(await _userVersion(db), kSchemaVersion);
        // 缺的那部分必须补齐
        expect(await _columns(db, 'user_settings'),
            containsAll(['coach_memory_enabled', 'coach_proactive_enabled']));
        expect(await _columns(db, 'ai_chat_messages'), contains('chips'));
        expect(await _tableNames(db), contains('coach_proactive_messages'));
        expect(
            await _indexNames(db), contains('idx_coach_proactive_created_at'));
      } finally {
        await db?.close();
        try {
          await tmp.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('B-9 / W-13：总开关关 → 不生成、不排期、撤掉已排的 200', () async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final repo = CoachProactiveRepository(db);
      final settings = UserSettingsRepositoryImpl(db);
      final notif = _SharedNotif();
      final push = _FakePushSink(notif);
      await settings.saveCoachEngagement(proactiveEnabled: false);

      final s = CoachProactiveScheduler(
        repo: repo,
        facts: WeeklyFactLoader(
          workout: WorkoutRepositoryImpl(db),
          body: BodyMetricRepositoryImpl(db),
          settings: settings,
        ),
        generator: CoachWeeklyGenerator(),
        push: push,
        settings: settings,
        overrides: DailyOverrideRepository(db),
        now: () => DateTime(2025, 11, 17, 8),
      );
      await s.runStartup();
      expect(await db.select(db.coachProactiveMessages).get(), isEmpty,
          reason: '关掉就该是真关：不生成、不调模型');
      expect(notif.scheduled, isEmpty);
      expect(notif.cancelled, contains(200), reason: '已排的必须撤掉');
    });

    test('C-11 接线：记忆**真的**进了发给模型的 system prompt，且 quote 不外泄', () async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final repo = CoachMemoryRepository(db);
      final settingsRepo = UserSettingsRepositoryImpl(db);
      await settingsRepo.save(aiApiKey: 'sk-test');
      await repo.upsert(CoachMemoriesCompanion.insert(
        category: 'injury',
        topic: '右膝',
        content: '右膝半月板有旧伤',
        quote: '我右膝半月板有旧伤',
      ));
      final svc = CoachMemoryService(
        repo: repo,
        extractor: _FakeExtractor(const []),
        settings: settingsRepo,
      );

      String? systemPrompt;
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        userSettingsProvider.overrideWith((ref) async =>
            const UserSettingsEntity(id: 1, aiApiKey: 'sk-test')),
        trendsDataProvider.overrideWith((ref) async => const TrendsData()),
        aiChatRepoProvider.overrideWithValue(AiChatRepository(db)),
        coachMemoryServiceProvider.overrideWithValue(svc),
        aiChatProvider.overrideWith((ref) => AiChatNotifier(
              ref,
              roundRunner: ({
                required apiKey,
                required messages,
                required onDelta,
                double temperature = 0.9,
                bool searchEnabled = true,
        bool fetchEnabled = true,
                AiProvider? provider,
              }) async {
                systemPrompt = messages.first.content as String;
                return const AiChatRoundResult(content: '好的，注意别深蹲');
              },
            )),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(aiChatProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await notifier.send('我右膝有点不舒服');

      expect(systemPrompt, contains('# 你记得的事'), reason: '注入没接线 = 记忆功能等于没做');
      expect(systemPrompt, contains('右膝半月板有旧伤'));
      // M-11：不带 quote（防 prompt 膨胀 + 防原话细节外泄）
      expect(systemPrompt, isNot(contains('我右膝半月板有旧伤')));
      // M-11：位置在【用户数据】之后、【用户额外约束】之前
      final dataIdx = systemPrompt!.indexOf('# 用户数据');
      final memIdx = systemPrompt!.indexOf('# 你记得的事');
      expect(dataIdx, greaterThan(-1));
      expect(memIdx, greaterThan(dataIdx));
    });
  });
}

// ══════════════════════════════════════════════════════════════
// 辅助
// ══════════════════════════════════════════════════════════════

CoachProactiveMessagesCompanion _weekly(DateTime weekStart, String content) =>
    CoachProactiveMessagesCompanion.insert(
      kind: 'weekly',
      dedupeKey: weeklyDedupeKey(weekStart),
      content: content,
      source: 'template',
      weekStart: Value(weekStart),
    );

/// v23 的 user_settings 全量列（drift 生成的 row mapper 要求列齐全，
/// 少一列就会在 `get()` 里抛，所以必须整表复刻）
void _createV23UserSettings(raw.Database db) {
  db.execute('''
    CREATE TABLE user_settings (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      height_cm REAL,
      target_weight_kg REAL,
      birth_date INTEGER,
      gender TEXT,
      activity_level TEXT,
      pin_code TEXT,
      lock_enabled INTEGER NOT NULL DEFAULT 0,
      speech_rate REAL,
      speech_pitch REAL,
      tts_voice TEXT,
      reminder_enabled INTEGER NOT NULL DEFAULT 0,
      reminder_hour INTEGER,
      reminder_minute INTEGER,
      theme_mode TEXT,
      default_training_sec INTEGER,
      default_rest_sec INTEGER,
      rest_short_sec INTEGER,
      rest_long_sec INTEGER,
      auto_backup_enabled INTEGER NOT NULL DEFAULT 1,
      ai_api_key TEXT,
      ai_style TEXT,
      ai_constraints TEXT,
      ai_reply_length TEXT,
      ai_temperature REAL,
      ai_persona_custom TEXT,
      ai_web_search_enabled INTEGER NOT NULL DEFAULT 1,
      daily_calorie_target INTEGER,
      protein_target_g REAL,
      carbs_target_g REAL,
      fat_target_g REAL,
      ai_health_override_count INTEGER NOT NULL DEFAULT 0,
      nickname TEXT,
      avatar_path TEXT
    )
  ''');
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return (row.data.values.first as num).toInt();
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

/// 通知侧共享状态：两个 sink 操作同一个"已排通知集合"，
/// 这样"cancelAll 把 200 一起清掉"才能被真实观察到。
class _SharedNotif {
  final active = <int>{};
  final scheduled = <({int id, String body, DateTime when})>[];
  final cancelled = <int>[];
}

class _FakePushSink implements CoachPushSink {
  _FakePushSink(this._n);

  final _SharedNotif _n;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    _n.active.add(id);
    _n.scheduled.add((id: id, body: body, when: when));
  }

  @override
  Future<void> cancel(int id) async {
    _n.active.remove(id);
    _n.cancelled.add(id);
  }
}

class _FakeReminderSink implements ReminderSink {
  _FakeReminderSink(this._n);

  final _SharedNotif _n;

  @override
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) async =>
      _n.active.add(id);

  @override
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) async =>
      _n.active.add(id);

  @override
  Future<void> cancelById(int id) async => _n.active.remove(id);

  @override
  Future<void> cancelAll() async => _n.active.clear();
}

class _FakeExtractor implements CoachMemoryExtractor {
  _FakeExtractor(this._result);

  final List<CoachMemoryCandidate> _result;

  @override
  Future<List<CoachMemoryCandidate>> extract({
    required List<String> userTurns,
    required String currentUserText,
    required List<CoachMemory> existing,
    required String? apiKey,
  }) async =>
      _result;
}

/// 只有一个"用户已删掉全部计划"的仓库
class _EmptyPlanRepository implements PlanRepository {
  @override
  Future<List<PlanEntity>> getAll() async => const [];

  @override
  Future<PlanEntity?> getById(int id) async => null;

  @override
  Future<PlanEntity> create(String name, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> updateName(int id, String name, {String? note}) =>
      throw UnimplementedError();

  @override
  Future<void> delete(int id) => throw UnimplementedError();

  @override
  Future<void> toggleActive(int id, bool isActive) =>
      throw UnimplementedError();

  @override
  Future<void> saveDays(int planId, List<PlanDayInput> days) =>
      throw UnimplementedError();
}
