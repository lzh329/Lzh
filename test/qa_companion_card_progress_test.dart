import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/trends/presentation/widgets/companion_card.dart';

import 'fake_database.dart';

/// QA 补充：趋势页顶部「我的○○」卡的进度条口径。
///
/// 造的是**满档用户**（历史最大减重 10 斤 → 第 3 档，最高档），这是真实用户里
/// 最常见的一类（减够 5 斤就会进来）。此前全库没有任何测试 pump 过
/// `CompanionCard`，所以这里只需回答一个问题：
/// **满档时进度条的值是不是还在 0~1 之间**（`LinearProgressIndicator` 的
/// 构造断言要求如此，越界在 debug/CI 直接抛，release 画出来也不对）。
void main() {
  // ⚠️ 缺陷 D1（已报工程师）：满档时进度条 value = 1.5（越界）。
  // 修好后把 skip 去掉，这条就是回归门禁。实测证据见交付回执。
  testWidgets('满档（第 3 档）用户的进度条不得越界，且显示「已经全部解锁」',
      (tester) async {
    final db = fakeDatabase();
    addTearDown(db.close);

    // 起始 80 斤 → 最低 70 斤 → 历史最大减重 10 斤（超第 3 档阈值 5 斤）
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 1, 1), weightKg: 40));
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 2, 1), weightKg: 35));
    // 现在回到 75 斤（涨了），形态不得退档（C7）
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 3, 1), weightKg: 37.5));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) => UserSettingsRepositoryImpl(db).get()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CompanionCard())),
    ));
    await tester.pump();
    await tester.pump();

    // 1) 满档文案
    expect(find.text('已经全部解锁'), findsOneWidget);

    // 2) 进度条：value 必须在 [0,1]
    final bars = tester
        .widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .toList();
    expect(bars, isNotEmpty, reason: '趋势卡上有进度条');
    for (final bar in bars) {
      final v = bar.value;
      expect(v, isNotNull);
      expect(v! >= 0.0 && v <= 1.0, isTrue,
          reason: 'LinearProgressIndicator.value 必须是 0~1，实际 ${bar.value}');
    }
  });

  testWidgets('第 2 档用户的进度条同样不越界（边界：刚好 5 斤）', (tester) async {
    final db = fakeDatabase();
    addTearDown(db.close);

    // 起始 80 → 最低 75.4 → 4.6 斤：仍第 2 档，档内进度已接近 1
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 1, 1), weightKg: 40));
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 2, 1), weightKg: 37.7));

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) => UserSettingsRepositoryImpl(db).get()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CompanionCard())),
    ));
    await tester.pump();
    await tester.pump();

    for (final bar
        in tester.widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))) {
      final v = bar.value;
      expect(v! >= 0.0 && v <= 1.0, isTrue, reason: '实际 ${bar.value}');
    }
  });
}
