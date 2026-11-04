import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fittrack/features/workout/domain/week_summary.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_week_strip.dart';

import 'fakes/workout_harness.dart';

/// T-8 周日期条：周一为起点、训练橙点 / 称重蓝点 / 同日双点、左右翻周
void main() {
  // 2025-03-03 是周一（用于固定的日期断言）
  final monday = DateTime(2025, 3, 3);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('周一为起点：第一格是周一的日号，第七格是周日', (tester) async {
    await tester.pumpWidget(host(WorkoutWeekStrip(
      weekStart: monday,
      selected: monday,
      markedDates: const {},
      weighDates: const {},
      onSelect: (_) {},
      onPrev: () {},
      onNext: () {},
    )));

    expect(find.text('3'), findsOneWidget, reason: '周一 = 3 月 3 日');
    expect(find.text('9'), findsOneWidget, reason: '周日 = 3 月 9 日');
    // 周标签序列固定「一 … 日」
    for (final label in ['一', '二', '三', '四', '五', '六', '日']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('训练日橙点、称重日蓝点、同日双点', (tester) async {
    int countDots(WidgetTester t, Color color) => t
        .widgetList<Container>(find.byType(Container))
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == color)
        .length;

    // 基准：没有任何标记时，两种颜色各只有**图例**里那一个
    await tester.pumpWidget(host(WorkoutWeekStrip(
      weekStart: monday,
      selected: monday,
      markedDates: const {},
      weighDates: const {},
      onSelect: (_) {},
      onPrev: () {},
      onNext: () {},
    )));
    final baseTraining = countDots(tester, WorkoutWeekStrip.trainingDotColor);
    final baseWeigh = countDots(tester, WorkoutWeekStrip.weighDotColor);
    expect(baseTraining, 1, reason: '图例「训练」');
    expect(baseWeigh, 1, reason: '图例「称重」');

    // 周三（3/5）有训练 + 称重（同日双点）；周五（3/7）只有称重
    await tester.pumpWidget(host(WorkoutWeekStrip(
      weekStart: monday,
      selected: monday,
      markedDates: {DateTime(2025, 3, 5)},
      weighDates: {DateTime(2025, 3, 5), DateTime(2025, 3, 7)},
      onSelect: (_) {},
      onPrev: () {},
      onNext: () {},
    )));

    expect(countDots(tester, WorkoutWeekStrip.trainingDotColor),
        baseTraining + 1,
        reason: '只有周三有训练');
    expect(countDots(tester, WorkoutWeekStrip.weighDotColor), baseWeigh + 2,
        reason: '周三 + 周五各一个');
  });

  testWidgets('点某天回调 onSelect，日期是真实日期对象', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(host(WorkoutWeekStrip(
      weekStart: monday,
      selected: monday,
      markedDates: const {},
      weighDates: const {},
      onSelect: (d) => picked = d,
      onPrev: () {},
      onNext: () {},
    )));

    await tester.tap(find.text('6'));
    await tester.pump();

    expect(picked, DateTime(2025, 3, 6));
  });

  testWidgets('左右箭头分别回调 onPrev / onNext', (tester) async {
    var prev = 0;
    var next = 0;
    await tester.pumpWidget(host(WorkoutWeekStrip(
      weekStart: monday,
      selected: monday,
      markedDates: const {},
      weighDates: const {},
      onSelect: (_) {},
      onPrev: () => prev++,
      onNext: () => next++,
    )));

    await tester.tap(find.byTooltip('上一周'));
    await tester.tap(find.byTooltip('下一周'));
    await tester.pump();

    expect(prev, 1);
    expect(next, 1);
  });

  group('页面级：翻周后选中日 = 新周周一（T-8 后半）', () {
    late WorkoutHarness harness;

    setUp(() async {
      await initializeDateFormatting('zh_CN');
      harness = WorkoutHarness();
    });
    tearDown(() => harness.dispose());

    testWidgets('点左箭头 → 周头变成上一周，选中日回到那一周的周一', (tester) async {
      await harness.seedWorkout(date: DateTime.now(), exerciseIds: const [1]);
      await tester.pumpWidget(harness.app(initialLocation: '/workout/records'));
      await tester.pump();
      await tester.pump();

      final thisMonday = WeekSummaryCalc.weekOf(DateTime.now());
      final lastMonday = thisMonday.subtract(const Duration(days: 7));

      await tester.tap(find.byTooltip('上一周'));
      await tester.pump();

      // 周头是「10月26日 - 11月1日」这种复合文本，所以用 textContaining
      expect(
          find.textContaining('${lastMonday.month}月${lastMonday.day}日'),
          findsWidgets,
          reason: '周头（范围文本）与选中日都应落在上一周');
      // 上周没有训练 → 该天明细为空态
      expect(find.text('这天没有训练'), findsOneWidget);
    });
  });
}
