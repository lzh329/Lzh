import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart' show appRouteObserver;
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_bubble.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'fake_database.dart';

/// 嘎教练入口（用户反馈：入口丢了）
///
/// 旧行为：点角色只播动作，气泡才是入口 —— 而气泡只在有未读时出现，
/// 等于把唯一的聊天入口藏进了一个条件分支里。
/// 新行为：**点角色直接进教练**；长按换形象；动作改为"进入首页自动播一次"。
void main() {
  late AppDatabase db;
  late GoRouter router;

  const allAssets = <String>[
    'assets/guga3d/guga_fat_head.png',
    'assets/guga3d/guga_fat_body.png',
    'assets/characters/nuonuo_1.png',
    'assets/characters/phoebe_1.png',
  ];

  setUp(() {
    db = fakeDatabase();
    DashboardPage.autoPlayInterval = const Duration(seconds: 30);
  });
  tearDown(() async {
    DashboardPage.autoPlayInterval = const Duration(seconds: 30);
    await db.close();
  });

  String location() =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  Widget host() {
    router = GoRouter(
      // 生产 router 注册了同一个 observer：首页"从教练页返回自动播一次"靠它
      observers: [appRouteObserver],
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(
          path: '/ai/coach',
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('嘎教练')),
            body: Center(
              child: TextButton(
                onPressed: () => router.pop(),
                child: const Text('返回首页'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/settings/character',
          builder: (_, __) => Scaffold(
            appBar: AppBar(title: const Text('我的形象')),
            body: Center(
              child: TextButton(
                onPressed: () => router.pop(),
                child: const Text('返回首页'),
              ),
            ),
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // 首页数据走空对象：把 DB IO 全绕开，只测手势与导航
        dashboardDataProvider.overrideWith((ref) async => const DashboardData()),
        userSettingsProvider.overrideWith(
            (ref) async => const UserSettingsEntity(id: 1, characterId: 'nuonuo')),
        bodyWeightsJinProvider.overrideWith((ref) async => const <double>[]),
        characterAssetManifestProvider
            .overrideWith((ref) async => allAssets.toSet()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// 返回首页后**不能**用 `pumpAndSettle`：首页的呼吸动画是无限循环，
  /// 永远 settle 不了。用手动几帧代替。
  Future<void> settleBack(WidgetTester tester) async {
    await tester.pump(); // 触发 pop
    await tester.pump(const Duration(milliseconds: 300)); // 转场
    await tester.pump(const Duration(milliseconds: 50)); // didPopNext + 自动播放
  }

  /// 进入首页并等角色画出来（空舞台 → CharacterView）
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pump(); // 设置/清单到达
    await tester.pump(); // 角色挂上
    await tester.pump(const Duration(milliseconds: 16));
  }

  testWidgets('点角色 → 进 /ai/coach（不再只是播动作）', (tester) async {
    await pumpHome(tester);
    expect(find.byType(CharacterView), findsOneWidget);

    await tester.tap(find.byType(CharacterView));
    await tester.pumpAndSettle();

    expect(location(), '/ai/coach');
    expect(find.text('嘎教练'), findsOneWidget);
  });

  testWidgets('点台词气泡 → 也是 /ai/coach（气泡入口保留）', (tester) async {
    await pumpHome(tester);

    // 按组件定位，不猜台词内容（台词会随自动播放轮换）
    expect(find.byType(CharacterBubble), findsOneWidget);
    await tester.tap(find.byType(CharacterBubble));
    await tester.pumpAndSettle();

    expect(location(), '/ai/coach');
  });

  testWidgets('长按角色 → 进 /settings/character（换形象保留）', (tester) async {
    await pumpHome(tester);

    await tester.longPress(find.byType(CharacterView));
    await tester.pumpAndSettle();

    expect(location(), '/settings/character');
    expect(find.text('我的形象'), findsOneWidget);
  });

  group('C-6 切换角色：「我是○○」窗口（1.5s）', () {
    testWidgets('切换后 1.5s 内说「我是○○」，窗口结束回日常台词', (tester) async {
      // 用 StateProvider 驱动 settings：改一次 = 用户切了一次角色
      final selected = StateProvider<String>((ref) => 'nuonuo');
      router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, __) => const DashboardPage())],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          dashboardDataProvider
              .overrideWith((ref) async => const DashboardData()),
          selected.overrideWith((ref) => 'nuonuo'),
          userSettingsProvider.overrideWith((ref) async => UserSettingsEntity(
              id: 1, characterId: ref.watch(selected))),
          bodyWeightsJinProvider.overrideWith((ref) async => const <double>[]),
          characterAssetManifestProvider
              .overrideWith((ref) async => allAssets.toSet()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // 首帧是日常台词（不是 intro）
      expect(find.text(kNuonuoIntroLine), findsNothing);

      // 切到菲比
      final container = ProviderScope.containerOf(
          tester.element(find.byType(DashboardPage)));
      container.read(selected.notifier).state = 'phoebe';
      await tester.pump(); // settings 重算
      await tester.pump(); // 重建

      expect(find.text(kPhoebeIntroLine), findsOneWidget,
          reason: '切换后 1.5s 内必须说「我是○○」（决策 2）');

      // 窗口到点（Timer 1.5s）→ 回日常台词池
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.text(kPhoebeIntroLine), findsNothing);
      expect(find.text(kPhoebeLinesByTier[1]!.first), findsOneWidget);
    });
  });

  group('动作改为自动播放（点角色已让位给"进教练"）', () {
    testWidgets('进入首页自动播一次', (tester) async {
      await pumpHome(tester);
      final character =
          tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(character.actionCount, 1,
          reason: '首帧之后要自动播一次，否则角色像张静态图');
    });

    testWidgets('30s 内从教练页返回：不再播（避免每次返回都抽搐）', (tester) async {
      await pumpHome(tester);
      final character =
          tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(character.actionCount, 1);

      // 自动播放后 1.5s 内是"动作冷却"，先等冷却过去，否则点击本身播不了，
      // 这条测试就会因为冷却而不是节流而"通过"（假绿）
      await tester.pump(CharacterView.tapCooldown);
      await tester.tap(find.byType(CharacterView));
      await tester.pumpAndSettle();
      expect(location(), '/ai/coach');
      expect(character.actionCount, 2, reason: '点击会播一次（_startAction）');

      await tester.pump(CharacterView.tapCooldown); // 过冷却，但没过 30s 节流
      await tester.tap(find.text('返回首页'));
      await settleBack(tester);

      expect(location(), '/');
      expect(character.actionCount, 2, reason: '30s 节流内返回不该再播');
    });

    testWidgets('超过 30s 再返回：会再播一次（节流可被跨过）', (tester) async {
      // 把节流窗口压到 0，等价于"距上次播放已超过 30s"
      DashboardPage.autoPlayInterval = Duration.zero;
      await pumpHome(tester);
      final character =
          tester.state<CharacterViewState>(find.byType(CharacterView));
      final afterFirstEntry = character.actionCount;

      await tester.pump(CharacterView.tapCooldown);
      await tester.tap(find.byType(CharacterView));
      await tester.pumpAndSettle();
      final afterTap = character.actionCount;
      expect(afterTap, afterFirstEntry + 1);

      await tester.pump(CharacterView.tapCooldown); // 过冷却（节流窗口本来就是 0）
      await tester.tap(find.text('返回首页'));
      await settleBack(tester);

      expect(character.actionCount, afterTap + 1,
          reason: '距上次播放超过窗口 → 返回首页要再播一次');
    });

    testWidgets('长按不播动作（只跳页）', (tester) async {
      await pumpHome(tester);
      final character =
          tester.state<CharacterViewState>(find.byType(CharacterView));
      final before = character.actionCount;

      await tester.longPress(find.byType(CharacterView));
      await tester.pumpAndSettle();

      expect(character.actionCount, before,
          reason: '长按是"我去换形象"，不该顺手播一段动画');
    });
  });
}
