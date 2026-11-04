/// 首页用到的两个**纯日期计算**（无 UI、无 DB、可单测）。
///
/// 为什么从 `dashboard_page.dart` 搬出来：
/// ① 页面已经贴近 300 行纪律，而这两个函数是"算"不是"画"；
/// ② 连续打卡天数的边界（今天没记但昨天记了、跨月、跨年）值得单独测，
///    埋在 State 里只能靠点界面才验证得到。
library;

/// 同一自然日（忽略时分秒）
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 连续打卡天数：从**今天**（今天还没记就从昨天）往前连续有记录的天数。
///
/// [now] 只为可测而注入，线上不传（取系统时间）。
///
/// 口径说明：今天没记不算断 —— 用户早上的时候今天本来还没记，
/// 直接归零会让"连续 12 天"在每天 00:00 变成"0 天"，看着像丢数据。
int calcStreak(List<DateTime> dates, {DateTime? now}) {
  if (dates.isEmpty) return 0;
  final days = dates.map((d) => DateTime(d.year, d.month, d.day)).toSet();
  final today = now ?? DateTime.now();
  var cursor = DateTime(today.year, today.month, today.day);
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}
