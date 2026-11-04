import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/domain/ai_tool_specs.dart';
import 'package:fittrack/features/ai/domain/ai_tool_router.dart';
import 'package:fittrack/features/ai/domain/coach_abilities.dart';
import 'package:fittrack/features/ai/presentation/pages/coach_abilities_page.dart';

/// 「嘎教练能做什么」页：内容来自工具面常量，不手抄
void main() {
  group('文案覆盖率（防漂移）', () {
    test('每个合并 action 都有中文文案', () {
      expect(CoachAbilities.missingWriteKeys(), isEmpty,
          reason: '新增 action 忘写文案会在这里暴露');
    });

    test('每个只读工具都有中文文案', () {
      expect(CoachAbilities.missingReadKeys(), isEmpty);
    });

    test('只读清单与 AiToolSpecs.readOnlyTools 一致（顺序表不许漂移）', () {
      expect(AiToolSpecsOrder.readOnly.toSet(), AiToolSpecs.readOnlyTools);
    });

    test('写清单数量 = 路由表 action 总数', () {
      final total = AiMergedTools.actions.values.fold<int>(0, (a, b) => a + b.length);
      expect(CoachAbilities.writeAbilities(), hasLength(total));
    });

    test('危险项来自 isMergedDestructive，不是手写', () {
      final dangerous = CoachAbilities.writeAbilities()
          .where((w) => w.destructive)
          .map((w) => w.key)
          .toSet();
      expect(dangerous, containsAll([
        'erase:records',
        'erase:all',
        'workout:delete',
        'template:delete',
        'goal:delete',
        'body:delete_measurement',
      ]));
      expect(dangerous, isNot(contains('workout:log')));
      expect(dangerous, isNot(contains('body:update_measurement')));
    });
  });

  group('页面渲染', () {
    testWidgets('三段标题都在，且危险项带「删除类」红标', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: CoachAbilitiesPage()));
      await tester.pump();

      expect(find.text('嘎教练能做什么'), findsOneWidget);
      expect(find.text('能查'), findsOneWidget);

      // ListView 懒构建：往下滚才能看到后两段
      await tester.scrollUntilVisible(find.text('能改'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('能改'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('会自动做'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('会自动做'), findsOneWidget);
    });

    testWidgets('危险项都标了「删除类」，普通项没有', (tester) async {
      // 直接断言行组件：数量由 isMergedDestructive 推导，不手写期望值
      final writes = CoachAbilities.writeAbilities();
      final expected = writes.where((w) => w.destructive).length;
      expect(expected, greaterThan(0));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final w in writes)
                  AbilityRow(text: w.text, destructive: w.destructive),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();

      // 全部行都渲染时，「删除类」数量正好等于危险项数
      expect(find.text('删除类'), findsNWidgets(expected));
    });

    testWidgets('只读段渲染了 7 项', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: CoachAbilitiesPage()));
      await tester.pump();
      for (final r in CoachAbilities.readAbilities()) {
        expect(find.text(r.text.label), findsOneWidget,
            reason: '缺少只读能力「${r.text.label}」');
      }
    });
  });
}
