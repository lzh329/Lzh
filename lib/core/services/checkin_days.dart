/// 累计打卡天数（中间断了不清零）
///
/// 口径与"连续打卡"共用同一数据源：某天有体重记录或训练记录即算打卡。
/// 只做「去重到天 + 计数」，不判断连续性 —— 连续性由 streak 那套负责。
///
/// 为什么单独抽纯函数：形象档位改按打卡天数判定后，这个数字会直接影响
/// 用户看到的形象，必须能穷举测（同一天多条记录只算一天这种边界最容易错）。
int countCheckinDays(Iterable<DateTime> dates) {
  final days = <String>{};
  for (final d in dates) {
    days.add('${d.year}-${d.month}-${d.day}');
  }
  return days.length;
}
