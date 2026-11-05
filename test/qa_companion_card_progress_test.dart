import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/trends/presentation/widgets/companion_card.dart';

import 'fake_database.dart';

/// QA 补充：趋势页顶部「我的○○」卡的进度条口径。
///
/// 形态口径 = 累计打卡天数（0/7/21 → 1/2/3 档）。满档 = 打卡 21 天。
/// 回答一个问题：**满档时进度条的值是不是还在 0~1 之间**
/// （`LinearProgressIndicator` 越界在 debug/CI 直接抛，release 画出来也不对）。
void main() {
  testWidgets('满档（第 3 档）用户的进度条不得越界，且显示「已解锁全部样子」',
      (tester) async {
    final db = fakeDatabase();
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) => UserSettingsRepositoryImpl(db).get()),
      checkinDaysProvider.overrideWith((ref) => const AsyncData<int>(21)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: CompanionCard())),
    ));
    await tester.pump();
    await tester.pump();

    // 1) 满档文案
    expect(find.text('已解锁全部样子'), findsOneWidget);

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

  testWidgets('第 2 档用户的进度条同样不越界（边界：刚好 7 天）', (tester) async {
    final db = fakeDatabase();
    addTearDown(db.close);

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) => UserSettingsRepositoryImpl(db).get()),
      checkinDaysProvider.overrideWith((ref) => const AsyncData<int>(7)),
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
