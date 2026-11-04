import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart';
import 'package:fittrack/features/trends/presentation/pages/trends_page.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';

import 'fake_database.dart';

/// 芯片跳转回归：从顶层路由（嘎教练）跳转必须用「顶层路由 + push」，
/// 既不能 push 底部 Tab（真机白屏），也不能 go（返回键回不到对话）。
void main() {
  late AppDatabase db;
  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  test('源码守卫：芯片跳转到去壳化顶层路由，不再 push 底部 Tab', () {
    final src = File('lib/features/ai/presentation/widgets/ai_chip_bar.dart')
        .readAsStringSync();
    expect(src.contains("'/workout/start'"), isTrue,
        reason: '去开练（无计划）要走顶层路由 /workout/start');
    expect(src.contains("push('/trends/view')"), isTrue,
        reason: '看趋势要走顶层路由 /trends/view');
    expect(src.contains("push('/settings')"), isTrue,
        reason: '设提醒要走顶层路由 /settings');
    // 关键：不能再 push 底部 Tab（真机白屏）或 push 带 redirect 的路由
    expect(src.contains("push('/workout')"), isFalse);
    expect(src.contains("push('/trends')"), isFalse);
    expect(src.contains("push('/profile')"), isFalse);
    expect(src.contains("'/workout/quick-start'"), isFalse);
    expect(src.contains("go('/workout')"), isFalse);
    expect(src.contains("go('/trends')"), isFalse);
  });

  Future<void> pumpAtTop(WidgetTester tester, ProviderContainer container) async {
    appRouter.go('/workout/records');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: appRouter),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('看趋势芯片 → push(/trends/view) 落地到趋势页，且能返回', (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      workoutTemplatesProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);
    await pumpAtTop(tester, container);

    appRouter.push('/trends/view');
    await tester.pumpAndSettle();

    expect(tester.any(find.byType(TrendsPage)), isTrue,
        reason: '看趋势跳转后必须渲染趋势页');
    expect(appRouter.canPop(), isTrue, reason: '返回键应能回到对话');
  });

  testWidgets('去开练芯片（无计划）→ push(/workout/start) 落地到训练页，且能返回',
      (tester) async {
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      workoutTemplatesProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);
    await pumpAtTop(tester, container);

    appRouter.push('/workout/start');
    await tester.pumpAndSettle();

    expect(tester.any(find.byType(QuickStartPage)), isTrue,
        reason: '去开练（无活跃计划）跳转后必须渲染训练页');
    expect(appRouter.canPop(), isTrue, reason: '返回键应能回到对话');
  });
}
