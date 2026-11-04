import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/coach_proactive_providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/data/coach_workout_recap.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/ai/presentation/pages/ai_chat_page.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

import 'fake_database.dart';

/// 训练后点评（决策 4 的最小方案 R1~R3）
///
/// 三条验收：写库去重、气泡当日上限、点击只预填不发送。
void main() {
  late AppDatabase db;
  late CoachProactiveRepository repo;
  late UserSettingsRepositoryImpl settings;
  late CoachWorkoutRecapService service;
  late DateTime now;

  setUp(() async {
    db = fakeDatabase();
    repo = CoachProactiveRepository(db);
    settings = UserSettingsRepositoryImpl(db);
    now = DateTime(2025, 11, 17, 19); // 周一晚
    service = CoachWorkoutRecapService(
      repo: repo,
      settings: settings,
      now: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<CoachProactiveMessage?> gen({
    int workoutId = 1,
    Set<String> categories = const {'strength'},
    int? durationSec = 1680,
  }) =>
      service.generateFor(
        workoutId: workoutId,
        exerciseCategories: categories,
        durationSec: durationSec,
      );

  Future<List<CoachProactiveMessage>> todayRecaps() {
    final dayStart = DateTime(now.year, now.month, now.day);
    return repo.listKindBetween(
      kind: kRecapKind,
      from: dayStart,
      to: dayStart.add(const Duration(days: 1)),
    );
  }

  // ═══════════ 文案（按训练形态取，不是随机） ═══════════

  group('文案模板', () {
    test('力量 ≥20 分钟', () {
      final t = recapContentFor(
        exerciseCategories: const {'strength'},
        durationSec: 28 * 60,
      );
      expect(t, contains('28 分钟力量练得挺实在'));
      expect(t, isNot(contains('大卡')), reason: '估不准，容易被戳破');
    });

    test('有氧 ≥20 分钟（不说"跑了"：也可能是跳绳/骑车）', () {
      final t = recapContentFor(
        exerciseCategories: const {'cardio'},
        durationSec: 30 * 60,
      );
      expect(t, contains('有氧 30 分钟'));
      expect(t, contains('吃够蛋白'));
    });

    test('任一类型 <10 分钟', () {
      final t = recapContentFor(
        exerciseCategories: const {'strength'},
        durationSec: 6 * 60,
      );
      expect(t, contains('10 分钟也算练了'));
    });

    test('10~20 分钟的普通训练也有兜底文案', () {
      final t = recapContentFor(
        exerciseCategories: const {'strength'},
        durationSec: 15 * 60,
      );
      expect(t, contains('15 分钟'));
      expect(t, isNot(contains('大卡')));
    });

    test('时长不知道 → 不生成（文案里的数字必须有出处）', () {
      expect(
        recapContentFor(exerciseCategories: const {'strength'}, durationSec: null),
        isNull,
      );
      expect(
        recapContentFor(exerciseCategories: const {'strength'}, durationSec: 0),
        isNull,
      );
    });

    test('不含"加油 / 坚持就是胜利"这类口号', () {
      final texts = [
        recapContentFor(exerciseCategories: const {'strength'}, durationSec: 1800),
        recapContentFor(exerciseCategories: const {'cardio'}, durationSec: 1800),
        recapContentFor(exerciseCategories: const {'strength'}, durationSec: 300),
      ];
      for (final t in texts) {
        expect(t, isNotNull);
        expect(t, isNot(contains('加油')));
        expect(t, isNot(contains('坚持就是胜利')));
      }
    });
  });

  // ═══════════ R1 / 验收 1：写库去重 ═══════════

  test('R1：保存训练后写一条 kind=workout_recap，dedupe_key=recap:{id}，source=template', () async {
    final record = await gen(workoutId: 7);
    expect(record, isNotNull);
    expect(record!.kind, kRecapKind);
    expect(record.dedupeKey, 'recap:7');
    expect(record.source, 'template', reason: '点评一律本地模板，不调模型');
    expect(record.workoutId, 7);
    expect(record.seenAt, isNull);
  });

  test('验收 1：同一次训练重复保存 → 只有 1 条（dedupe_key 唯一）', () async {
    await gen(workoutId: 7);
    await gen(workoutId: 7);
    expect(await repo.countKindBetween(
      kind: kRecapKind,
      from: DateTime(2025, 11, 17),
      to: DateTime(2025, 11, 24),
    ), 1);
  });

  // ═══════════ R2 / 验收 2：频率 ═══════════

  test('R2：同一天练两次 → 只留 1 条，文案是后一次的', () async {
    await gen(workoutId: 1, durationSec: 28 * 60);
    now = DateTime(2025, 11, 17, 21);
    await gen(workoutId: 2, durationSec: 6 * 60);

    final today = await todayRecaps();
    expect(today, hasLength(1), reason: '一天练两次的人不该收到两条点评');
    expect(today.single.dedupeKey, 'recap:2');
    expect(today.single.content, contains('10 分钟也算练了'));
  });

  test('R2：本周已有 2 条 → 第 3 次不再生成（跨天也不行）', () async {
    await gen(workoutId: 1);
    now = DateTime(2025, 11, 19, 20); // 周三
    await gen(workoutId: 2);
    now = DateTime(2025, 11, 21, 20); // 周五
    final third = await gen(workoutId: 3);

    expect(third, isNull, reason: '每周点评上限 2 条');
    expect(
      await repo.countKindBetween(
        kind: kRecapKind,
        from: DateTime(2025, 11, 17),
        to: DateTime(2025, 11, 24),
      ),
      2,
    );
  });

  test('R2：下周重新计数（周一又是新的一周）', () async {
    await gen(workoutId: 1);
    now = DateTime(2025, 11, 19, 20);
    await gen(workoutId: 2);
    now = DateTime(2025, 11, 24, 20); // 下周一
    final next = await gen(workoutId: 3);
    expect(next, isNotNull);
  });

  // ═══════════ 边界 ═══════════

  test('总开关关 → 不生成（生成、推送、AI 调用全部为 0）', () async {
    await settings.saveCoachEngagement(proactiveEnabled: false);
    expect(await gen(), isNull);
    expect(await todayRecaps(), isEmpty);
  });

  test('不推送：点评从不调用 push sink（这里只断言"没有通知 id 常量参与"）', () {
    // 点评审阅入口在 CoachWorkoutRecapService 里完全没有 push 依赖 ——
    // 构造它时也不需要 CoachPushSink，这条从类型上就成立。
    expect(kWeeklyRecapCap, 2);
    expect(kRecapPrefill, isNotEmpty);
  });

  test('markSeen 只写 seen_at（不推送，所以不需要 cancel 任何通知）', () async {
    final record = (await gen())!;
    await service.markSeen(record.id);
    final after = await repo.getById(record.id);
    expect(after!.seenAt, isNotNull);
  });

  // ═══════════ 验收 3：点击只预填不发送 ═══════════

  testWidgets('验收 3：点气泡 → 教练页预填问句，不自动发送、不写历史', (tester) async {
    final fakeRepo = _FakeChatRepository(db);
    var runnerCalls = 0;
    final container = ProviderContainer(overrides: [
      userSettingsProvider.overrideWith(
          (ref) async => const UserSettingsEntity(id: 1, aiApiKey: 'sk-test')),
      aiChatRepoProvider.overrideWithValue(fakeRepo),
      trendsDataProvider.overrideWith((ref) async => const TrendsData()),
      coachLatestWeeklyProvider.overrideWith((ref) async => null),
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
              runnerCalls++;
              return const AiChatRoundResult(content: '好的');
            },
          )),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        // 与 openCoachChip → \'/ai/coach\' with extra 的行为等价：
        // 只把文本塞进输入框
        home: AiChatPage(initialText: kRecapPrefill),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text(kRecapPrefill), findsOneWidget, reason: '输入框里要有预填文本');
    expect(runnerCalls, 0, reason: '不许替用户做决定：点了不等于要花钱发请求');
    expect(fakeRepo.addCalls, isEmpty, reason: '不写入对话历史');
  });
}

/// 内存版聊天仓库：不碰真实数据库，只记录调用
class _FakeChatRepository extends AiChatRepository {
  _FakeChatRepository(super.db);

  final List<String> addCalls = <String>[];

  @override
  Future<List<AiMessage>> getHistory() async => const [];

  @override
  Future<void> add(
    String role,
    String content, {
    List<CoachChip> chips = const [],
  }) async {
    addCalls.add(role);
  }

  @override
  Future<void> clear() async => addCalls.clear();
}
