/// 本周摘要的纯函数（T11 口径）。
///
/// 三件事都在这里算完，页面只负责排版：
/// 1. 本周训练次数
/// 2. 本周总时长（分钟，四舍五入；null 时长不计入）
/// 3. 连续有训练的周数（**允许本周为空**）
///
/// 为什么"连续周数允许本周为空"：否则每个周一早上都显示「连续 0 周」，
/// 用户会以为功能坏了。口径是从最近一个有训练的周往前连续计数。
class WeekSummary {
  /// 本周训练次数
  final int weekCount;

  /// 本周总时长（分钟）
  final int weekMinutes;

  /// 连续有训练的周数（本周还没练 → 从上周往前数，不中断）
  final int streakWeeks;

  const WeekSummary({
    required this.weekCount,
    required this.weekMinutes,
    required this.streakWeeks,
  });

  static const empty =
      WeekSummary(weekCount: 0, weekMinutes: 0, streakWeeks: 0);
}

abstract final class WeekSummaryCalc {
  /// 周一 00:00 为一周起点，**归一化到 `DateTime(y, m, d)`**（去掉时分秒）。
  ///
  /// 用真实日期算，不用"第几周编号"：跨年、跨月、夏令时都不会错位。
  static DateTime weekOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    // weekday: 周一 = 1 … 周日 = 7
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// [workouts] 是训练记录（只用到日期与时长），[now] 只用于确定"本周"（便于单测注入）。
  static WeekSummary of(
    List<({DateTime date, int? durationSec})> workouts, {
    required DateTime now,
  }) {
    if (workouts.isEmpty) return WeekSummary.empty;

    final currentWeek = weekOf(now);
    var weekCount = 0;
    var weekSeconds = 0;

    // 周集合：用于连续周数
    final weeks = <DateTime>{};
    for (final w in workouts) {
      final week = weekOf(w.date);
      weeks.add(week);
      if (week == currentWeek) {
        weekCount++;
        weekSeconds += w.durationSec ?? 0;
      }
    }

    // 连续周数：本周不在集合里 → 先退回一周（本周还没练：不计数、不中断）
    var cursor = currentWeek;
    if (!weeks.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 7));
    }
    var streak = 0;
    while (weeks.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 7));
    }

    return WeekSummary(
      weekCount: weekCount,
      // 四舍五入到分钟（(秒 + 30) ÷ 60 向下取整等价于四舍五入）
      weekMinutes: (weekSeconds / 60).round(),
      streakWeeks: streak,
    );
  }
}
