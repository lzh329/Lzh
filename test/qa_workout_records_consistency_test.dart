import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fittrack/features/workout/domain/week_summary.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_day_cell.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_record_card.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_week_summary.dart';

import 'fakes/workout_harness.dart';

/// QA 补充：T-7 / T-8 / T-11 的**三周真实数据**（不是单条记录）。
///
/// 已有测试每条都只造"今天一条"。真实用户是跨周的：本周 2 次、上周 1 次、
/// 上上周 1 次。这里抽查三件事与库一致：
///   ① 本周摘要三个数字（次数 / 时长 / 连续周数）；
///   ② 周条的打点（训练橙点、称重蓝点、同日双点）；
///   ③ 翻到上一周、点中那一天 → 明细条数 == 库里那天的条数。
void main() {
  late WorkoutHarness harness;
  late int squatId;

  setUp(() async {
    await initializeDateFormatting('zh_CN');
    harness = WorkoutHarness();
    squatId = await harness.seedExercise(name: '深蹲');
  });

  tearDown(() => harness.dispose());

  Future<void> pumpRecords(WidgetTester tester) async {
    await tester.pumpWidget(harness.app(initialLocation: '/workout/records'));
    await tester.pump();
    await tester.pump();
  }

  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  testWidgets('三周数据：摘要数字、周条打点、翻周明细都对得上库', (tester) async {
    final now = DateTime.now();
    final thisWeek = WeekSummaryCalc.weekOf(now);
    final lastWeek = thisWeek.subtract(const Duration(days: 7));
    final twoWeeksAgo = thisWeek.subtract(const Duration(days: 14));

    // 本周两次（各 12 分钟 = 720 秒 → 合计 24 分钟）
    final w1 = await harness.seedWorkout(
        date: thisWeek.add(const Duration(days: 0, hours: 20)),
        durationSec: 720,
        exerciseIds: [squatId],
        setsPerExercise: 3);
    final w2 = await harness.seedWorkout(
        date: thisWeek.add(const Duration(days: 2, hours: 19)),
        durationSec: 720,
        exerciseIds: [squatId]);
    // 上周一次、上上周一次（让"连续周数"= 3）
    final lastWeekDay = lastWeek.add(const Duration(days: 3, hours: 21));
    await harness.seedWorkout(
        date: lastWeekDay,
        durationSec: 600,
        exerciseIds: [squatId],
        setsPerExercise: 2);
    await harness.seedWorkout(
        date: twoWeeksAgo.add(const Duration(days: 5, hours: 18)),
        durationSec: 300,
        exerciseIds: [squatId]);

    // 上周那天还称过体重（蓝点）
    await harness.seedWeight(day(lastWeekDay), kg: 68);

    await pumpRecords(tester);

    // ① 摘要：本周 2 次 / 24 分钟 / 连续 3 周
    final summary =
        tester.widget<WorkoutWeekSummary>(find.byType(WorkoutWeekSummary)).summary;
    expect(summary.weekCount, 2);
    expect(summary.weekMinutes, 24);
    expect(summary.streakWeeks, 3, reason: '本周有练 + 上周 + 上上周 = 连续 3 周');
    // 数字确实渲染到了页面上
    expect(find.text('2'), findsWidgets);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('3'), findsWidgets);

    // ② 周条打点：本周第 1 天有训练点、没有称重点
    final cells = tester
        .widgetList<WorkoutDayCell>(find.byType(WorkoutDayCell))
        .toList();
    expect(cells, hasLength(7), reason: '一周 7 格');
    final monday = cells.first;
    expect(monday.date, day(thisWeek));
    expect(monday.hasMark, isTrue, reason: '本周一有训练 → 橙点');
    expect(monday.hasWeight, isFalse);

    // ③ 翻到上一周：点上周那天 → 明细 1 条，且组数是 2
    await tester.tap(find.byTooltip('上一周'));
    await tester.pumpAndSettle();

    final lastWeekCells = tester
        .widgetList<WorkoutDayCell>(find.byType(WorkoutDayCell))
        .toList();
    // 翻周后选中日 = 新周周一（T8）
    expect(lastWeekCells.first.date, day(lastWeek));
    expect(lastWeekCells.first.selected, isTrue);

    // 上周那天同时有训练和称重 → 双点
    final targetCell = lastWeekCells
        .firstWhere((c) => c.date == day(lastWeekDay));
    expect(targetCell.hasMark, isTrue, reason: '训练点');
    expect(targetCell.hasWeight, isTrue, reason: '称重点（同日双点）');

    await tester.tap(find.text('${lastWeekDay.day}').first);
    await tester.pumpAndSettle();

    // 库里的条数作为唯一事实来源
    final dbWorkouts = await harness.db.select(harness.db.workouts).get();
    final inDbThatDay =
        dbWorkouts.where((w) => day(w.date) == day(lastWeekDay)).length;
    expect(inDbThatDay, 1);
    expect(find.byType(WorkoutRecordCard), findsNWidgets(inDbThatDay));
    expect(find.textContaining('2 组'), findsOneWidget,
        reason: '那条记录是 2 组，卡片口径必须和库一致');

    // 明细页脚不是"今天"（选中日已换），说明翻周确实换了明细
    expect(find.text('今天'), findsNothing);
    // 顺带确认记录卡点进去是这条记录本身
    expect(w1, isNot(w2));
  });
}
