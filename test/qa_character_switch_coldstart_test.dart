import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/presentation/pages/character_page.dart';

import 'fake_database.dart';

/// QA 补充：C-5（杀进程后仍是所选角色）+ C-7（只升不降）的**数字现场**。
///
/// 形态口径 = 累计打卡天数（0/7/21 → 1/2/3 档），打卡 21 天 ⇒ 第 3 档。
/// 必须同时成立的结论：
///   ① 形态停在第 3 档（按打卡 21 天算），只升不降；
///   ② 首页/形象页不出现「累计减重」「胖了」「退档」这类措辞（口径分离 + 不用身材评价词）；
///   ③ 满档之后不再出现「再打卡 X 天换下一个样子」。
void main() {
  late AppDatabase db;

  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  List<String> visibleTexts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .where((t) => t.isNotEmpty)
      .toList();

  testWidgets('④ 切换后 1.5s 内说「我是○○」，窗口结束回日常台词（C-6）', (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider
          .overrideWith((ref) => UserSettingsRepositoryImpl(db).get()),
      dashboardDataProvider.overrideWith((ref) async => const DashboardData()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DashboardPage()),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 默认咕嘎：首次进入不播「我是○○」（isFirstBuild），直接日常台词
    expect(find.text(kGugaIntroLine), findsNothing);

    // 切到菲比
    await container.read(characterSelectionProvider).select(CharacterId.phoebe);
    await tester.pump();
    await tester.pump();

    expect(find.text(kPhoebeIntroLine), findsOneWidget,
        reason: '切换后 1.5s 内必须说「我是○○」（决策 2）');

    // 再切一次（菲比 → 糯糯）：台词必须换成糯糯的「我是○○」，
    // 不许把上一个角色的台词留在气泡里（C-6 的"不跨角色续播"在文案层的体现）
    await container.read(characterSelectionProvider).select(CharacterId.nuonuo);
    await tester.pump();
    await tester.pump();
    expect(find.text(kNuonuoIntroLine), findsOneWidget);
    expect(find.text(kPhoebeIntroLine), findsNothing);
  });

  test('① 杀进程重启（新容器 + 同一个库）仍是上次选的角色', () async {
    final first = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider
          .overrideWith((ref) => UserSettingsRepositoryImpl(db).get()),
    ]);
    await first.read(userSettingsProvider.future);
    await first.read(characterSelectionProvider).select(CharacterId.nuonuo);
    await first.read(userSettingsProvider.future);
    expect(first.read(currentCharacterProvider).id, CharacterId.nuonuo);
    first.dispose();

    final second = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider
          .overrideWith((ref) => UserSettingsRepositoryImpl(db).get()),
    ]);
    addTearDown(second.dispose);
    await second.read(userSettingsProvider.future);
    expect(second.read(currentCharacterProvider).id, CharacterId.nuonuo,
        reason: '重启后必须还是糯糯（写库了，不是内存态）');
    expect((await UserSettingsRepositoryImpl(db).get())!.characterId, 'nuonuo');
  });

  testWidgets('② 打卡 21 天：形态第 3 档，首页不出现「累计减重/胖了」',
      (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider
          .overrideWith((ref) => UserSettingsRepositoryImpl(db).get()),
      checkinDaysProvider.overrideWith((ref) => const AsyncData<int>(21)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DashboardPage()),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final spec = container.read(currentCharacterProvider);
    expect(spec.checkinDays, 21, reason: '形态口径 = 累计打卡天数');
    expect(spec.form, 3, reason: '21 天 ⇒ 第 3 档');
    expect(spec.isMaxForm, isTrue);
    expect(spec.remainToNextDays, isNull);

    final texts = visibleTexts(tester);
    for (final banned in ['累计减重', '胖了', '退档', '瘦了']) {
      expect(texts.any((t) => t.contains(banned)), isFalse,
          reason: '首页不许出现「$banned」');
    }
    // 满档后不该再提"再打卡 X 天"
    expect(texts.any((t) => t.contains('再打卡')), isFalse);
  });

  testWidgets('③ 形象页同样停在第 3 档；满档只出现「都解锁了」，不再提"等你解锁"',
      (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider
          .overrideWith((ref) => UserSettingsRepositoryImpl(db).get()),
      checkinDaysProvider.overrideWith((ref) => const AsyncData<int>(21)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CharacterPage()),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final texts = visibleTexts(tester);
    // 咕嘎 + 糯糯两张卡都是满档
    expect(texts.where((t) => t == '已打卡 21 天 · 已解锁全部样子').length, 2);
    expect(texts.any((t) => t.contains('等你解锁')), isFalse,
        reason: '满档时不许同时又出现"等你解锁"');
    expect(texts.any((t) => t.contains('换下一个样子')), isFalse);
    expect(texts.any((t) => t.contains('累计减重')), isFalse,
        reason: '形象页不许用趋势页的口径名');
    // 老规则：用户向不出现"形态"
    expect(texts.any((t) => t.contains('形态')), isFalse);

    // 当前样子：小咕嘎（第 3 档），糯糯是灰发版
    expect(texts.any((t) => t.contains('小咕嘎')), isTrue);
    expect(texts.any((t) => t.contains('糯糯（灰发版）')), isTrue);
  });
}
