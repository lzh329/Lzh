import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/ai_oneshot_service.dart';
import 'package:fittrack/core/services/coach_proactive_scheduler.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/core/services/coach_weekly_template.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';

import 'fake_database.dart';

/// 记录调用的假落点：通知插件在单测进程里不可用，没有这层就断言不了"没排期"
class _FakePushSink implements CoachPushSink {
  final scheduled = <({int id, String body, DateTime when})>[];
  final cancelled = <int>[];

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    scheduled.add((id: id, body: body, when: when));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}

/// 固定回一段正文的假 SSE 客户端
class _FakeAiClient extends http.BaseClient {
  _FakeAiClient(this.reply);

  final String reply;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final line = 'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': reply},
            },
          ],
        })}';
    final payload = '$line\n\ndata: [DONE]\n\n';
    return http.StreamedResponse(Stream.value(utf8.encode(payload)), 200);
  }
}

/// 永不返回的客户端（模拟"模型卡住"）
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

void main() {
  late AppDatabase db;
  late CoachProactiveRepository repo;
  late UserSettingsRepository settings;
  late WeeklyFactLoader facts;
  late _FakePushSink push;
  late DateTime now;

  /// 2025-11-17 是周一
  final monday = DateTime(2025, 11, 17);

  setUp(() {
    db = fakeDatabase();
    repo = CoachProactiveRepository(db);
    settings = UserSettingsRepositoryImpl(db);
    facts = WeeklyFactLoader(
      workout: WorkoutRepositoryImpl(db),
      body: BodyMetricRepositoryImpl(db),
      settings: settings,
    );
    push = _FakePushSink();
    now = DateTime(2025, 11, 17, 8); // 周一 08:00，离 09:00 还有一小时
  });

  tearDown(() async {
    await db.close();
  });

  CoachProactiveScheduler scheduler({CoachWeeklyGenerator? generator}) =>
      CoachProactiveScheduler(
        repo: repo,
        facts: facts,
        generator: generator ?? CoachWeeklyGenerator(),
        push: push,
        settings: settings,
        overrides: DailyOverrideRepository(db),
        now: () => now,
      );

  Future<void> addWorkout(DateTime date, {int durationSec = 1800}) async {
    await WorkoutRepositoryImpl(db).createWorkout(
      date: date,
      type: 'free',
      durationSec: durationSec,
      sets: const [],
    );
  }

  Future<void> addWeight(DateTime date, double kg) async {
    await BodyMetricRepositoryImpl(db).create(date: date, weightKg: kg);
  }

  // ═══════════ 周口径 ═══════════

  group('周口径（跨年安全）', () {
    test('mondayOf 取当周周一；跨年不会算错', () {
      expect(mondayOf(DateTime(2025, 11, 17, 23)), DateTime(2025, 11, 17));
      expect(mondayOf(DateTime(2025, 11, 23)), DateTime(2025, 11, 17));
      // 2026-01-01 是周四 → 周一 2025-12-29
      expect(mondayOf(DateTime(2026, 1, 1)), DateTime(2025, 12, 29));
    });

    test('dedupe key 只用年月日，不用"第几周编号"', () {
      expect(weeklyDedupeKey(DateTime(2025, 11, 17)), 'weekly:2025-11-17');
      expect(weeklyDedupeKey(DateTime(2026, 1, 5)), 'weekly:2026-01-05');
    });
  });

  // ═══════════ W-1 / W-9：只统计上周，缺数字不填 0 ═══════════

  test('W-1：只统计上周一到上周日，本周数据不参与', () async {
    await addWorkout(DateTime(2025, 11, 11, 19), durationSec: 1200);
    await addWorkout(DateTime(2025, 11, 13, 19), durationSec: 600);
    // 本周（周一当天）的训练不算
    await addWorkout(DateTime(2025, 11, 17, 7), durationSec: 3600);

    final f = await facts.load(now: now);
    expect(f.workoutCount, 2);
    expect(f.workoutMinutes, 30);
    expect(f.weekStart, monday, reason: 'weekStart = 投递周的周一');
    expect(f.dataStart, DateTime(2025, 11, 10));
    expect(f.dataEnd, DateTime(2025, 11, 16));
  });

  test('W-1：上周首尾体重取上周区间，本周体重不影响', () async {
    await addWeight(DateTime(2025, 11, 10), 70.0); // 140 斤
    await addWeight(DateTime(2025, 11, 16), 69.0); // 138 斤
    await addWeight(DateTime(2025, 11, 17), 68.0); // 本周，不算

    final f = await facts.load(now: now);
    expect(f.weightStartJin, 140);
    expect(f.weightEndJin, 138);
    expect(f.weightChangeKnown, isTrue);
    expect(f.weightChangeJin, -2);
    expect(f.weighInDays, 2);
  });

  test('W-9：上周只有 1 条体重 → 整段不提体重，文案里不出现「0.0 斤」', () async {
    await addWeight(DateTime(2025, 11, 12), 70.0);
    await addWorkout(DateTime(2025, 11, 12, 20));

    final f = await facts.load(now: now);
    expect(f.weightChangeKnown, isFalse);
    final text = CoachWeeklyTemplate.render(f);
    expect(text.contains('0.0 斤'), isFalse, reason: '0 是"真的 0"，不是"不知道"');
    expect(text.contains('体重从'), isFalse);
    expect(text.contains('体重没动'), isFalse, reason: '1 次称重算不出变化，说"没动"就是假精确');
  });

  // ═══════════ W-10：三档目标句 ═══════════

  test('W-10：0 次 / 1~2 次 / ≥3 次 → 三种目标句', () {
    expect(CoachWeeklyTemplate.goalLine(0), '先练 1 次，10 分钟也算');
    expect(CoachWeeklyTemplate.goalLine(1), '练 2 次，每次 15 分钟以上');
    expect(CoachWeeklyTemplate.goalLine(2), '练 2 次，每次 15 分钟以上');
    expect(CoachWeeklyTemplate.goalLine(3), '保持 3 次');
    expect(CoachWeeklyTemplate.goalLine(6), '保持 3 次');
  });

  test('W-10：0 次训练时文案给台阶，不追责', () {
    final f = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 0,
      workoutMinutes: 0,
      weighInDays: 0,
    );
    final text = CoachWeeklyTemplate.render(f);
    expect(text, contains('也没关系'));
    expect(text, contains('先练 1 次'));
    expect(text.contains('你没做到'), isFalse);
  });

  // ═══════════ W-4：推送时刻 ═══════════

  test('W-4：默认周一 09:00；reminderHour == 9 时顺延 10:00', () {
    expect(weeklyPushAt(weekStart: monday, reminderHour: null).hour, 9);
    expect(weeklyPushAt(weekStart: monday, reminderHour: 8).hour, 9);
    expect(weeklyPushAt(weekStart: monday, reminderHour: 9).hour, 10);
    // 用户把称重设成 10:00 → 周消息仍在 09:00（不同小时，不构成撞车）
    expect(weeklyPushAt(weekStart: monday, reminderHour: 10).hour, 9);
    expect(weeklyPushAt(weekStart: monday, reminderHour: 9).minute, 0);
  });

  // ═══════════ W-5 / W-6 / W-7 / W-13 / W-14 的决策层 ═══════════

  group('决定推不推（纯函数）', () {
    CoachPushDecision decide({
      bool enabled = true,
      bool seen = false,
      bool paused = false,
      bool fatigue = false,
      DateTime? at,
      int? hour,
    }) =>
        decideWeeklyPush(
          now: at ?? DateTime(2025, 11, 17, 8),
          weekStart: monday,
          reminderHour: hour,
          enabled: enabled,
          seen: seen,
          pausedOnWeekStart: paused,
          fatigueSuppressed: fatigue,
        );

    test('W-5：已读 → 不排', () {
      expect(decide(seen: true), CoachPushDecision.suppressSeen);
    });

    test('W-6：周一 09:00 之后（含周二）→ 不排、不补推', () {
      expect(decide(at: DateTime(2025, 11, 17, 9)),
          CoachPushDecision.suppressLate);
      expect(decide(at: DateTime(2025, 11, 18, 10)),
          CoachPushDecision.suppressLate);
    });

    test('W-7：周一 reminderPaused → 不排', () {
      expect(decide(paused: true), CoachPushDecision.suppressPaused);
    });

    test('W-13：总开关关 → 不排', () {
      expect(decide(enabled: false), CoachPushDecision.suppressDisabled);
    });

    test('W-14：连续 2 条未读 → 不排（仍生成）', () {
      expect(decide(fatigue: true), CoachPushDecision.suppressFatigue);
    });

    test('全部条件都过 → 排期', () {
      expect(decide(), CoachPushDecision.schedule);
    });
  });

  test('W-14：isFatigueSuppressed 只认"最近 2 条都未见"', () {
    CoachProactiveMessage m(DateTime? seen) => CoachProactiveMessage(
          id: 1,
          kind: 'weekly',
          dedupeKey: 'weekly:x',
          content: 'x',
          source: 'template',
          createdAt: DateTime(2025, 11, 17),
          weekStart: DateTime(2025, 11, 17),
          seenAt: seen,
        );

    expect(isFatigueSuppressed([]), isFalse);
    expect(isFatigueSuppressed([m(null)]), isFalse, reason: '只有 1 条不算疲劳');
    expect(isFatigueSuppressed([m(null), m(null)]), isTrue);
    expect(isFatigueSuppressed([m(null), m(DateTime(2025, 11, 10))]), isFalse,
        reason: '看到过一条就清零恢复');
  });

  // ═══════════ W-2 / W-3：幂等与单飞 ═══════════

  test('W-2：同一 weekStart 连续调两次生成逻辑，只产生 1 行记录', () async {
    final s = scheduler();
    await s.ensureWeeklyGenerated();
    await s.ensureWeeklyGenerated();
    expect(await db.select(db.coachProactiveMessages).get(), hasLength(1));
  });

  test('runStartup 单飞：并发调用共享同一个 Future，不会生成两条', () async {
    final s = scheduler();
    await Future.wait([s.runStartup(), s.runStartup()]);
    expect(await db.select(db.coachProactiveMessages).get(), hasLength(1));
  });

  // ═══════════ W-6 / W-7 / W-13：调度层集成 ═══════════

  test('W-6：周二 10:00 打开 → 记录已生成，但排期 0 次', () async {
    now = DateTime(2025, 11, 18, 10);
    await scheduler().runStartup();
    expect(await repo.getWeekly(monday), isNotNull, reason: '照常生成、照常内展');
    expect(push.scheduled, isEmpty, reason: '迟到的推送是错时噪音');
  });

  test('W-7：周一 reminderPaused → 记录已生成，排期 0 次', () async {
    await DailyOverrideRepository(db).upsert(
      date: monday,
      reminderPaused: true,
      source: 'user',
    );
    await scheduler().runStartup();
    expect(await repo.getWeekly(monday), isNotNull);
    expect(push.scheduled, isEmpty);
  });

  test('周一 08:00 且一切正常 → 排期一次，id 恒为 200，时刻 09:00', () async {
    await scheduler().runStartup();
    expect(push.scheduled, hasLength(1));
    expect(push.scheduled.single.id, kCoachWeeklyNotificationId);
    expect(kCoachWeeklyNotificationId, 200);
    expect(push.scheduled.single.when, DateTime(2025, 11, 17, 9));
  });

  test('称重提醒也是 9 点 → 周消息顺延到 10:00（不叠加两条）', () async {
    await settings.save(reminderHour: 9);
    await scheduler().runStartup();
    expect(push.scheduled.single.when, DateTime(2025, 11, 17, 10));
  });

  test('W-13：总开关关 → 生成 0 次、排期 0 次，且取消已排的 200', () async {
    await settings.saveCoachEngagement(proactiveEnabled: false);
    await scheduler().runStartup();
    expect(await db.select(db.coachProactiveMessages).get(), isEmpty);
    expect(push.scheduled, isEmpty);
    expect(push.cancelled, contains(kCoachWeeklyNotificationId));
  });

  test('已读后再 syncPush：不排期并撤掉 200（W5）', () async {
    final s = scheduler();
    await s.runStartup();
    expect(push.scheduled, hasLength(1));
    final record = (await repo.getWeekly(monday))!;
    await s.markSeen(record.id);

    push.scheduled.clear();
    await s.syncPush();
    expect(push.scheduled, isEmpty);
    expect(push.cancelled, contains(kCoachWeeklyNotificationId));
    expect((await repo.getWeekly(monday))!.seenAt, isNotNull);
  });

  // ═══════════ cancelAll 陷阱：所有会清空通知的入口都要补回 200 ═══════════

  test('关掉每日提醒（NotificationService.cancelAll）后 syncPush 把 200 补回来', () async {
    final s = scheduler();
    await s.runStartup();
    expect(
        push.scheduled.map((e) => e.id), contains(kCoachWeeklyNotificationId));

    // 模拟设置页「每日提醒」关掉时的 cancelAll()：插件侧把 200 也清了
    push.scheduled.clear();

    // 设置页在 cancelAll() 之后立刻补这一次
    await s.syncPush();
    expect(
        push.scheduled.map((e) => e.id), contains(kCoachWeeklyNotificationId),
        reason: '关提醒不许顺手把周消息一起废掉（周一 08:30 关 → 09:00 前无路径可补）');
  });

  test('源码守卫：settings_page 的 cancelAll() 之后必须紧跟 syncPush()', () {
    final source = File(
      'lib/features/settings/presentation/pages/settings_page.dart',
    ).readAsStringSync();
    final at = source.indexOf('NotificationService().cancelAll()');
    expect(at, greaterThan(-1), reason: '找不到关提醒的 cancelAll()，守卫失效');
    // 允许中间夹注释与换行，但必须是紧邻的下一个动作
    final window = source.substring(at, at + 500);
    expect(window.contains('syncPush()'), isTrue,
        reason: '删掉这行后，周一 08:30 关提醒的用户会静默丢失周消息，'
            '且没有任何报错');
  });

  // ═══════════ W-8：五级降级链 ═══════════

  group('W-8 降级链', () {
    final factsStub = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 2,
      workoutMinutes: 40,
      weighInDays: 2,
    );

    test('① 无 Key → 模板', () async {
      final draft = await CoachWeeklyGenerator()
          .build(facts: factsStub, settings: null, apiKey: null);
      expect(draft.source, 'template');
      expect(draft.content, CoachWeeklyTemplate.render(factsStub));
    });

    test('② 超时 → 模板（不重试、不抛异常）', () async {
      final text = await AiOneShotService.complete(
        apiKey: 'sk-test',
        messages: const [],
        client: _HangingClient(),
      );
      expect(text, isNull, reason: '空 messages 直接返回 null');
      // 真正验证超时：给一条 message + 永不返回的客户端
      final draft = await CoachWeeklyGenerator(
        client: _HangingClient(),
        aiTimeout: const Duration(milliseconds: 50),
      ).build(
        facts: factsStub,
        settings: null,
        apiKey: 'sk-test',
      );
      expect(draft.source, 'template');
    });

    test('③ 正文 < 40 字 → 模板', () async {
      final draft = await CoachWeeklyGenerator(client: _FakeAiClient('练得不错呀。'))
          .build(facts: factsStub, settings: null, apiKey: 'sk-test');
      expect(draft.source, 'template');
    });

    test('③ 正文 > 120 字 → 模板', () async {
      final long = '练' * 121;
      final draft = await CoachWeeklyGenerator(client: _FakeAiClient(long))
          .build(facts: factsStub, settings: null, apiKey: 'sk-test');
      expect(draft.source, 'template');
    });

    test('④ 命中禁用词（保证）→ 模板', () async {
      const bad = '上周练了两次很不错，我保证你这周一定能看到变化，继续保持这个节奏就行啦。';
      final draft = await CoachWeeklyGenerator(client: _FakeAiClient(bad))
          .build(facts: factsStub, settings: null, apiKey: 'sk-test');
      expect(draft.source, 'template');
    });

    test('⑤ 全部通过 → AI 正文（source=ai）', () async {
      const good = '上周练了 2 次、一共 40 分钟，比前一周稳。这周练 2 次，每次 15 分钟以上就够，'
          '顺手记 3 天体重吧。';
      expect(CoachWeeklyTemplate.isAcceptable(good), isTrue);
      final draft = await CoachWeeklyGenerator(client: _FakeAiClient(good))
          .build(facts: factsStub, settings: null, apiKey: 'sk-test');
      expect(draft.source, 'ai');
      expect(draft.content, good);
    });

    test('isAcceptable 边界：40 字与 120 字都算合格', () {
      expect(CoachWeeklyTemplate.isAcceptable('好' * 40), isTrue);
      expect(CoachWeeklyTemplate.isAcceptable('好' * 120), isTrue);
      expect(CoachWeeklyTemplate.isAcceptable('好' * 39), isFalse);
      expect(CoachWeeklyTemplate.isAcceptable('好' * 121), isFalse);
    });
  });

  // ═══════════ W-12：周消息不进对话历史 ═══════════

  test('W-12：周消息只落 coach_proactive_messages，不进 ai_chat_messages', () async {
    await scheduler().runStartup();
    final record = (await repo.getWeekly(monday))!;
    final chat = await db.select(db.aiChatMessages).get();
    expect(chat, isEmpty);
    expect(chat.any((c) => c.content == record.content), isFalse);
    // 清聊天记录不影响周消息
    await db.delete(db.aiChatMessages).go();
    expect(await repo.getWeekly(monday), isNotNull);
  });

  // ═══════════ 模板文案形态 ═══════════

  test('模板：三种典型形态（有变化 / 没变化 / 没训练）都能渲染出来', () {
    final base = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 3,
      workoutMinutes: 90,
      weighInDays: 3,
      weightStartJin: 140.0,
      weightEndJin: 138.0,
    );
    final changed = CoachWeeklyTemplate.render(base);
    expect(changed, contains('上周练了 3 次'));
    expect(changed, contains('体重从 140.0 斤'));
    expect(changed, contains('保持 3 次'));

    final flat = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 2,
      workoutMinutes: 40,
      weighInDays: 3,
      weightStartJin: 140.0,
      weightEndJin: 140.05,
    );
    expect(CoachWeeklyTemplate.render(flat), contains('体重没动很正常'));

    final none = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 0,
      workoutMinutes: 0,
      weighInDays: 0,
    );
    final noneText = CoachWeeklyTemplate.render(none);
    expect(noneText, contains('没怎么练'));
    expect(noneText, isNot(contains('0 次')), reason: '不许把"没练"说成数字断言');
  });

  test('模板含「顺手记 3 天体重」只在称重天数 < 3 时出现', () {
    final many = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 1,
      workoutMinutes: 20,
      weighInDays: 4,
    );
    final few = WeeklyFacts(
      weekStart: _mondayConst,
      workoutCount: 1,
      workoutMinutes: 20,
      weighInDays: 2,
    );
    expect(CoachWeeklyTemplate.render(many).contains('顺手记 3 天体重'), isFalse);
    expect(CoachWeeklyTemplate.render(few), contains('顺手记 3 天体重'));
  });

  // ═══════════ 通知 id 段位 ═══════════

  test('200 不在称重段（100~106）内，也不在训练段（0~99）内', () {
    expect(
        kCoachWeeklyNotificationId >= 100 && kCoachWeeklyNotificationId < 200,
        isFalse);
    expect(kCoachWeeklyNotificationId < 100, isFalse);
    expect(kCoachWeeklyNotificationId, 200);
  });
}

/// 常量位置使用（const 上下文里不能写 DateTime(...)，用一个 final 兜住）
final DateTime _mondayConst = DateTime(2025, 11, 17);
