import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 「今天」的唯一来源（当天 0 点）
///
/// 为什么要有它：`dashboardDataProvider` 之前在**计算那一刻**取
/// `DateTime.now()`，而 provider 只在数据变更 / 下拉刷新时失效。
/// App 从后台恢复时不会重算 → 隔夜回来还显示"昨天"的打卡状态。
///
/// 规则：
/// - 所有日维度数据（今日训练 / 今日体重 / 今日热量 / 打卡）都从这里取日期，
///   不各自 `DateTime.now()`
/// - App 回到前台时调 [applyToday]，**日期变了才**写新值（同一天 resume 不重建）
/// - 不用 Timer 轮询：跨零点靠"回前台 / 下一次读"触发
final todayKeyProvider = StateProvider<DateTime>((ref) => todayMidnight());

/// 取某时刻的当天 0 点（默认现在）
DateTime todayMidnight([DateTime? now]) {
  final d = now ?? DateTime.now();
  return DateTime(d.year, d.month, d.day);
}

/// 把「今天」同步进 [ctrl]；返回是否真的变了
///
/// 只在日期不同才写：避免每次 resume 都让下游 provider 白重建一轮。
bool applyToday(StateController<DateTime> ctrl, {DateTime? now}) {
  final t = todayMidnight(now);
  if (ctrl.state == t) return false;
  ctrl.state = t;
  return true;
}
