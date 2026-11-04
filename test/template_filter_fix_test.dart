import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_cards.dart';

/// 用户报修两件事的回归门禁：
/// 1. 类型/难度筛选之前只对「推荐模板」生效，漏了「我的模板」
/// 2. 模板卡颜色与难度/类型脱钩（原来是种子随机 accentKey）
WorkoutTemplateEntity _t(
  int id, {
  required String type,
  required String difficulty,
  required String name,
}) =>
    WorkoutTemplateEntity(
      id: id,
      name: name,
      difficulty: difficulty,
      focus: '全身',
      type: type,
      minutes: 20,
    );

void main() {
  group('模板卡配色', () {
    test('力量 vs 有氧主色不同；同类型内难度递进也不同', () {
      final sEntry = _t(1, type: 'strength', difficulty: '入门', name: 'A');
      final sHigh = _t(2, type: 'strength', difficulty: '高阶', name: 'B');
      final cEntry = _t(3, type: 'cardio', difficulty: '入门', name: 'C');
      final cHigh = _t(4, type: 'cardio', difficulty: '高阶', name: 'D');

      expect(templateAccent(sEntry), isNot(templateAccent(cEntry)),
          reason: '力量与有氧必须是两套色，不能同色');
      expect(templateAccent(sEntry), isNot(templateAccent(sHigh)),
          reason: '同一类型内难度必须递进变色');
      expect(templateAccent(cEntry), isNot(templateAccent(cHigh)));

      expect(templateGradient(sEntry).length, 2);
      expect(templateGradient(cEntry).first,
          isNot(templateGradient(sEntry).first));
    });

    test('未知难度回落到某档颜色，不抛异常', () {
      final weird = _t(5, type: 'strength', difficulty: '宗师', name: 'E');
      expect(templateAccent(weird), isNotNull);
      expect(templateGradient(weird).length, 2);
    });
  });

  testWidgets('类型筛选同时对「我的模板」生效', (tester) async {
    final templates = [
      _t(1, type: 'strength', difficulty: '入门', name: '我的力量'),
      _t(2, type: 'cardio', difficulty: '中阶', name: '我的有氧'),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutTemplatesProvider.overrideWith((ref) async => templates),
      ],
      child: const MaterialApp(home: QuickStartPage()),
    ));
    await tester.pumpAndSettle();

    // 默认「全部」：两个我的模板都在
    expect(find.text('我的力量'), findsOneWidget);
    expect(find.text('我的有氧'), findsOneWidget);

    // 切到「力量」
    await tester.tap(find.text('力量').first);
    await tester.pumpAndSettle();

    expect(find.text('我的力量'), findsOneWidget);
    expect(find.text('我的有氧'), findsNothing,
        reason: '类型筛选必须对「我的模板」生效，不能只筛推荐模板');
  });

  testWidgets('难度筛选同时对「我的模板」生效', (tester) async {
    final templates = [
      _t(1, type: 'strength', difficulty: '入门', name: '入门力量'),
      _t(2, type: 'strength', difficulty: '高阶', name: '高阶力量'),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workoutTemplatesProvider.overrideWith((ref) async => templates),
      ],
      child: const MaterialApp(home: QuickStartPage()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('入门').first);
    await tester.pumpAndSettle();

    expect(find.text('入门力量'), findsOneWidget);
    expect(find.text('高阶力量'), findsNothing,
        reason: '难度筛选必须对「我的模板」生效');
  });
}
