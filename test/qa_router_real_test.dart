import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_records_page.dart';

import 'fake_database.dart';

/// QA 补充：**真实 appRouter** 的路由顺序（T-3 / T-6 / T-18）。
///
/// 为什么不用 `test/fakes/workout_harness.dart`：那个脚手架把路由表**抄了一遍**。
/// 抄本再绿也不能证明 `lib/core/router/app_router.dart` 的顺序是对的 ——
/// 有人把 `/workout/records` 挪到 `/workout/:id` 后面，抄本测试仍然全绿，
/// 而线上点「训练记录」会进「无效的训练ID」。所以这里直接驱动生产 router。
///
/// 深链的模拟方式：Android intent 进来就是先给 router 一个 location 再挂树，
/// 等价于 `appRouter.go(location)` + `pumpWidget`，因此这里用同一顺序。
void main() {
  late AppDatabase db;

  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  String location() => appRouter
      .routerDelegate.currentConfiguration.matches.last.matchedLocation;

  Future<void> pumpAt(WidgetTester tester, String initial) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      workoutTemplatesProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);

    appRouter.go(initial);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump();
  }

  group('T-3/T-6 `/workout/records` 不能被当成训练 id', () {
    test('源码守卫：声明顺序上 records 早于 :id（顺序写反就红）', () {
      final src = File('lib/core/router/app_router.dart').readAsStringSync();
      final records = src.indexOf("path: '/workout/records'");
      final byId = src.indexOf("path: '/workout/:id'");
      expect(records, greaterThan(0), reason: '路由必须存在');
      expect(byId, greaterThan(0), reason: '路由必须存在');
      expect(records < byId, isTrue,
          reason: 'go_router 按声明顺序匹配：records 必须排在 :id 之前');
      // stats / active 这些固定段同样不能被 :id 吃掉
      for (final fixed in ['/workout/stats', '/workout/active']) {
        expect(src.indexOf("path: '$fixed'") < byId, isTrue, reason: fixed);
      }
    });

    testWidgets('go(/workout/records) → 训练记录页，不是「无效的训练ID」', (tester) async {
      await pumpAt(tester, '/workout/records');
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutRecordsPage), findsOneWidget);
      expect(find.text('无效的训练ID'), findsNothing);
    });

    testWidgets('深链（冷启动直接进 /workout/records）同样正确', (tester) async {
      await pumpAt(tester, '/workout/records');
      await tester.pumpAndSettle();

      expect(location(), '/workout/records');
      expect(find.byType(WorkoutRecordsPage), findsOneWidget);
      expect(find.text('无效的训练ID'), findsNothing);
    });

    testWidgets('数字 id 仍然进详情（不是被 records 抢走）', (tester) async {
      await pumpAt(tester, '/workout/42');
      await tester.pumpAndSettle();

      expect(location(), '/workout/42');
      expect(find.byType(WorkoutRecordsPage), findsNothing);
    });
  });

  group('T-18 老深链 /workout/quick-start', () {
    testWidgets('go(/workout/quick-start) → 落到 /workout，不白屏', (tester) async {
      await pumpAt(tester, '/workout/quick-start');
      await tester.pumpAndSettle();

      expect(location(), '/workout');
      expect(find.byType(QuickStartPage), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(AppBar), matching: find.text('训练')),
          findsOneWidget,
          reason: '落到训练 Tab（底部导航也叫"训练"，所以要限定在 AppBar 里）');
    });
  });
}
