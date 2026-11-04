import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/router/app_router.dart';

/// 一级页（带底部导航的壳）按返回键：第一次只提示，不立即退出。
///
/// 子页是壳外的独立路由，返回键在子页上是正常 pop，不受这里影响。
void main() {
  testWidgets('一级页按返回：第一次只提示「再按一次退出应用」', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => ScaffoldWithNav(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const Text('主控页')),
            GoRoute(path: '/workout', builder: (_, __) => const Text('训练页')),
            GoRoute(path: '/trends', builder: (_, __) => const Text('趋势页')),
            GoRoute(path: '/profile', builder: (_, __) => const Text('我的页')),
          ],
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 第一次按返回：不得退出，而是弹出提示
    await WidgetsBinding.instance.handlePopRoute();
    await tester.pump();

    expect(find.text('再按一次退出应用'), findsOneWidget,
        reason: '一级页第一次按返回必须给「再按一次」提示，不能直接退到桌面');
    // 页面仍在（没有退到桌面 = 没有崩溃、路由没被 pop 掉）
    expect(find.text('主控页'), findsOneWidget);
  });

  testWidgets('子页返回不受影响：正常 pop 回壳，不弹提示', (tester) async {
    final router = GoRouter(
      initialLocation: '/sub',
      routes: [
        // 一级壳
        GoRoute(
          path: '/',
          builder: (_, __) => const ScaffoldWithNav(child: Text('主控页')),
        ),
        // 子页（壳外）
        GoRoute(path: '/sub', builder: (_, __) => const Text('子页面')),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 子页返回 → 直接 pop，不出现「再按一次」提示
    await WidgetsBinding.instance.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('再按一次退出应用'), findsNothing,
        reason: '子页返回是普通 pop，不该被双击退出逻辑拦截');
  });
}
