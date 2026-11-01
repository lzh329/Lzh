import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/coach_proactive_providers.dart';
import 'package:fittrack/core/services/coach_proactive_scheduler.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/features/ai/data/coach_memory_repository.dart';
import 'package:fittrack/features/ai/presentation/pages/coach_memory_page.dart';
import 'package:fittrack/features/ai/presentation/widgets/coach_weekly_bubble.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'fake_database.dart';

/// 内展 UI + 设置集成（W-11 / W-13 / M-13 / M-14 / M-16）
void main() {
  late AppDatabase db;
  late CoachProactiveRepository proactive;
  late CoachMemoryRepository memories;
  late UserSettingsRepositoryImpl settings;
  late _FakePushSink push;

  final monday = mondayOf(DateTime.now());

  setUp(() {
    db = fakeDatabase();
    proactive = CoachProactiveRepository(db);
    memories = CoachMemoryRepository(db);
    settings = UserSettingsRepositoryImpl(db);
    push = _FakePushSink();
  });

  tearDown(() async {
    await db.close();
  });

  /// 统一的最小覆写：真内存库 + 假通知落点（不碰平台通道）
  List<Override> overrides({UserSettingsEntity? entity}) => [
        databaseProvider.overrideWithValue(db),
        coachPushSinkProvider.overrideWithValue(push),
        userSettingsProvider.overrideWith(
            (ref) async => entity ?? const UserSettingsEntity(id: 1)),
      ];

  Future<void> pumpIt(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: overrides()),
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<CoachProactiveMessage> seedWeekly({String? content}) async {
    final record = await proactive.insertIfAbsent(
      CoachProactiveMessagesCompanion.insert(
        kind: 'weekly',
        dedupeKey: weeklyDedupeKey(monday),
        content: content ?? '上周练了 2 次，一共 40 分钟。这周练 2 次就行。',
        source: 'template',
        weekStart: Value(monday),
      ),
    );
    return record!;
  }

  // ═══════════ W-11：渲染即已读 ═══════════

  testWidgets('W-11：pump 首页气泡 → seen_at 非空，且本次仍能看到正文', (tester) async {
    final record = await seedWeekly();
    await pumpIt(tester, const CoachWeeklyBubble());
    await tester.pumpAndSettle();

    final after = await proactive.getById(record.id);
    expect(after!.seenAt, isNotNull, reason: '渲染即写 seen_at');
    expect(find.text(record.content), findsOneWidget,
        reason: '写已读不能让气泡在同一帧消失，否则用户永远读不到');

    // 重新进首页（State 重建）→ 已读的不再出现
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpIt(tester, const CoachWeeklyBubble());
    await tester.pumpAndSettle();
    expect(find.text(record.content), findsNothing);
  });

  testWidgets('W-11：没有未读 → 气泡是 0 高度占位（不留空档）', (tester) async {
    await pumpIt(tester, const CoachWeeklyBubble());
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
  });

  // ═══════════ W-13：总开关关 → 气泡不出现 ═══════════

  testWidgets('W-13：coach_proactive_enabled=false → 气泡找不到（且已排的通知被撤）', (tester) async {
    await seedWeekly();
    await settings.saveCoachEngagement(proactiveEnabled: false);
    final disabled = (await settings.get())!;
    expect(disabled.coachProactiveEnabled, isFalse);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: overrides(entity: disabled)),
      child: const MaterialApp(home: Scaffold(body: CoachWeeklyBubble())),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('上周练了'), findsNothing);
  });

  testWidgets('教练页卡片：已读也保留（与首页气泡两个口径）', (tester) async {
    final record = await seedWeekly();
    await proactive.markSeen(record.id, DateTime.now());

    await pumpIt(tester, const CoachWeeklyCard());
    await tester.pumpAndSettle();
    expect(find.text(record.content), findsOneWidget);
  });

  // ═══════════ M-13：记忆页分组与空态 ═══════════

  testWidgets('M-13：空态给出说明', (tester) async {
    await pumpIt(tester, const CoachMemoryPage());
    await tester.pumpAndSettle();
    expect(find.textContaining('教练还没记住什么'), findsOneWidget);
    expect(find.textContaining('发给你的 AI 模型'), findsOneWidget,
        reason: '页头必须写明记忆会随 prompt 发给模型');
  });

  testWidgets('M-13：按 5 类分组，标题带条数', (tester) async {
    await memories.upsert(_mem('diet', '香菜', '不吃香菜'));
    await memories.upsert(_mem('diet', '牛奶', '乳糖不耐'));
    await memories.upsert(_mem('injury', '右膝', '右膝半月板有旧伤'));

    await pumpIt(tester, const CoachMemoryPage());
    await tester.pumpAndSettle();

    expect(find.text('忌口 · 2'), findsOneWidget);
    expect(find.text('伤病 · 1'), findsOneWidget);
    expect(find.text('不吃香菜'), findsOneWidget);
  });

  testWidgets('M-13：开关关闭 → 顶部提示 + 列表仍在（数据保留）', (tester) async {
    await memories.upsert(_mem('diet', '香菜', '不吃香菜'));
    await settings.saveCoachEngagement(memoryEnabled: false);
    final entity = (await settings.get())!;

    await tester.pumpWidget(UncontrolledProviderScope(
      container: ProviderContainer(overrides: overrides(entity: entity)),
      child: const MaterialApp(home: CoachMemoryPage()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('记忆已关闭'), findsOneWidget);
    expect(find.text('不吃香菜'), findsOneWidget, reason: '关掉 ≠ 删除');
  });

  // ═══════════ M-14：删单条无确认 + 可撤销 ═══════════

  testWidgets('M-14：点删除不弹确认框，出现「撤销」，点撤销条目回来', (tester) async {
    await memories.upsert(_mem('diet', '香菜', '不吃香菜'));
    await pumpIt(tester, const CoachMemoryPage());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    // 等 SnackBar 完全进场，否则点不到「撤销」
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byType(AlertDialog), findsNothing,
        reason: '删单条是回到安全态，不是破坏性操作');
    expect(find.text('不吃香菜'), findsNothing);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(find.text('不吃香菜'), findsOneWidget);
    expect(await memories.count(), 1);
  });

  // ═══════════ M-16：清除全部必须二次确认 ═══════════

  testWidgets('M-16：点「清除全部记忆」出现确认框；取消后一条都不删', (tester) async {
    await memories.upsert(_mem('diet', '香菜', '不吃香菜'));
    await pumpIt(tester, const CoachMemoryPage());
    await tester.pumpAndSettle();

    await tester.tap(find.text('清除全部记忆'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await memories.count(), 1);
  });

  // ═══════════ W-14：降频在 UI 上仍然内展 ═══════════

  testWidgets('W-14：连续 2 周未读只影响推送，气泡照常出现', (tester) async {
    // 造上上周 + 上周两条未读
    for (final ws in [
      monday.subtract(const Duration(days: 14)),
      monday.subtract(const Duration(days: 7)),
    ]) {
      await proactive.insertIfAbsent(CoachProactiveMessagesCompanion.insert(
        kind: 'weekly',
        dedupeKey: weeklyDedupeKey(ws),
        content: '旧的周消息',
        source: 'template',
        weekStart: Value(ws),
      ));
    }
    final record = await seedWeekly();

    await pumpIt(tester, const CoachWeeklyBubble());
    await tester.pumpAndSettle();
    expect(find.text(record.content), findsOneWidget, reason: '停推不等于停展');
  });
}

CoachMemoriesCompanion _mem(String category, String topic, String content) =>
    CoachMemoriesCompanion.insert(
      category: category,
      topic: topic,
      content: content,
      quote: content,
    );

class _FakePushSink implements CoachPushSink {
  final scheduled = <int>[];
  final cancelled = <int>[];

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async =>
      scheduled.add(id);

  @override
  Future<void> cancel(int id) async => cancelled.add(id);
}
