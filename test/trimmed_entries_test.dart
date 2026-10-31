import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/settings/presentation/pages/settings_page.dart';
import 'package:fittrack/features/trends/presentation/pages/trends_page.dart';

/// 2026-10-31 用户拍板精简：趋势页去掉「行为统计」「打卡日历」，
/// 我的页去掉「目标管理」入口。此测试防止这几块被顺手加回来。
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Widget host(ProviderContainer container, Widget child) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: child),
      );

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('趋势页不再有行为统计与打卡日历', (tester) async {
    await tester.pumpWidget(host(buildContainer(), const TrendsPage()));
    await tester.pumpAndSettle();

    expect(find.text('行为统计'), findsNothing);
    expect(find.text('打卡日历'), findsNothing);
    // 体重主线还在（防止误删整页）
    expect(find.text('趋势'), findsOneWidget);
  });

  testWidgets('我的页不再有目标管理入口，其余档案入口保留', (tester) async {
    await tester.pumpWidget(host(buildContainer(), const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('目标管理'), findsNothing);
    expect(find.text('个人档案'), findsOneWidget);
    expect(find.text('动作库'), findsOneWidget);
    expect(find.text('身体相册'), findsOneWidget);
  });
}
