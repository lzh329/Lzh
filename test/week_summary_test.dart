import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/domain/week_summary.dart';

/// T-11 摘要三个数字的口径（纯函数，无 UI、无 DB）
///
/// 口径：周一 00:00 起算；本周时长四舍五入到分钟（null 时长不计入）；
/// 连续周数**允许本周为空**（从最近一个有训练的周往前连续计数）。
void main() {
  // 2025-03-05 是周三；所在周周一 = 2025-03-03
  final now = DateTime(2025, 3, 5, 21, 30);

  test('weekOf：周一为起点，且归一化到 00:00（时分秒清零）', () {
    expect(WeekSummaryCalc.weekOf(DateTime(2025, 3, 3, 0, 1)),
        DateTime(2025, 3, 3));
    expect(WeekSummaryCalc.weekOf(DateTime(2025, 3, 9, 23, 59)),
        DateTime(2025, 3, 3), reason: '周日属于当周');
    expect(WeekSummaryCalc.weekOf(DateTime(2025, 3, 10, 0, 0)),
        DateTime(2025, 3, 10), reason: '周一属于新的一周');
    // 跨年：2025-01-01 是周三 → 所在周周一是 2024-12-30
    expect(WeekSummaryCalc.weekOf(DateTime(2025, 1, 1)),
        DateTime(2024, 12, 30));
  });

  test('跨两周数据：上周 3 次、本周 1 次 → 本周次数 = 1', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 2, 25, 20), durationSec: 600), // 上周二
      (date: DateTime(2025, 2, 27, 20), durationSec: 900), // 上周四
      (date: DateTime(2025, 2, 28, 20), durationSec: 300), // 上周五
      (date: DateTime(2025, 3, 4, 20), durationSec: 1200), // 本周二
    ], now: now);

    expect(summary.weekCount, 1);
    expect(summary.weekMinutes, 20, reason: '本周只有 1200 秒 = 20 分钟');
    expect(summary.streakWeeks, 2);
  });

  test('本周 0 次但上周有 → 连续周数按上周往前数（不显示 0）', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 2, 25, 20), durationSec: 600),
      (date: DateTime(2025, 2, 18, 20), durationSec: 600),
      (date: DateTime(2025, 2, 11, 20), durationSec: 600),
    ], now: now);

    expect(summary.weekCount, 0);
    expect(summary.weekMinutes, 0);
    expect(summary.streakWeeks, 3,
        reason: '否则每个周一早上都显示「连续 0 周」，看起来像功能坏了');
  });

  test('中间断一周 → 从断点重算', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 3, 4, 20), durationSec: 600), // 本周
      (date: DateTime(2025, 2, 25, 20), durationSec: 600), // 上周
      // 2/17 那周空着
      (date: DateTime(2025, 2, 11, 20), durationSec: 600),
      (date: DateTime(2025, 2, 4, 20), durationSec: 600),
    ], now: now);

    expect(summary.streakWeeks, 2, reason: '断点之后不再计入');
  });

  test('null 时长不计入，秒数四舍五入到分钟', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 3, 4, 20), durationSec: null),
      (date: DateTime(2025, 3, 5, 20), durationSec: 89), // 1.48 分 → 1
      (date: DateTime(2025, 3, 5, 21), durationSec: 31), // 0.52 分 → 1
    ], now: now);

    expect(summary.weekCount, 3);
    expect(summary.weekMinutes, 2, reason: '120 秒 = 2 分钟');
  });

  test('空数据：全 0，不崩（也不显示 NaN）', () {
    final summary = WeekSummaryCalc.of(const [], now: now);
    expect(summary.weekCount, 0);
    expect(summary.weekMinutes, 0);
    expect(summary.streakWeeks, 0);
  });

  test('同一天多次训练算多次（次数口径 = 记录条数）', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 3, 4, 8), durationSec: 300),
      (date: DateTime(2025, 3, 4, 20), durationSec: 300),
    ], now: now);
    expect(summary.weekCount, 2);
    expect(summary.weekMinutes, 10);
    expect(summary.streakWeeks, 1);
  });

  test('未来日期的训练记录不计入"本周"（脏数据防御）', () {
    final summary = WeekSummaryCalc.of([
      (date: DateTime(2025, 3, 20, 20), durationSec: 600), // 下下周
      (date: DateTime(2025, 3, 4, 20), durationSec: 600),
    ], now: now);
    expect(summary.weekCount, 1);
    expect(summary.streakWeeks, 1, reason: '连续周数从本周往前数，未来记录不影响');
  });
}
