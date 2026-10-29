import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 时间范围档位（与页面上的 周/月/季/全部 一一对应）
enum WeightRange {
  week,
  month,
  quarter,
  all;

  /// 页面上的字符串 key → 枚举（未知值按 [WeightRange.month]）
  static WeightRange fromKey(String key) => switch (key) {
        'week' => WeightRange.week,
        'quarter' => WeightRange.quarter,
        'all' => WeightRange.all,
        _ => WeightRange.month,
      };

  /// 往前推多少天；null = 不限
  int? get days => switch (this) {
        WeightRange.week => 7,
        WeightRange.month => 30,
        WeightRange.quarter => 90,
        WeightRange.all => null,
      };

  /// 每个桶多少天（"全部"自动按数据跨度选，见 [bucketWeightSeries]）
  int get bucketDays => switch (this) {
        WeightRange.week => 1,
        WeightRange.month => 7,
        WeightRange.quarter => 14,
        WeightRange.all => 30,
      };

  String get label => switch (this) {
        WeightRange.week => '周',
        WeightRange.month => '月',
        WeightRange.quarter => '季',
        WeightRange.all => '全部',
      };
}

/// 一个时间桶的统计结果
class WeightBucket {
  /// 桶起点（含）
  final DateTime start;

  /// 桶终点（不含）
  final DateTime end;

  /// 桶内平均体重（kg）
  final double avgKg;

  /// 桶内最低体重（kg）
  final double minKg;

  /// 桶内记录条数
  final int count;

  const WeightBucket({
    required this.start,
    required this.end,
    required this.avgKg,
    required this.minKg,
    required this.count,
  });

  /// 横轴标签：周档显示 M/D，其余显示 M/D 起
  String get label => '${start.month}/${start.day}';
}

/// 按时间桶聚合体重序列（**纯函数**，页面不参与任何计算）
///
/// 聚合规则（改之前先读）：
/// 1. **只看体重**：`weightKg <= 0` 的记录不参与（历史脏数据 / 只有围度没有
///    体重的记录）—— 一条 0kg 会把整桶平均值拉到不可读；
/// 2. 周桶以**周一**为界（[startOfWeek]），不是「7 天前」这种滑动窗口 ——
///    滑动窗口每次刷新都会变，用户对不上"上周到底多重"；
/// 3. 空桶**不补 0**：没有记录的桶直接不出现，否则图上会出现一排 0kg 的柱子。
List<WeightBucket> bucketWeightSeries(
  List<BodyMetricEntity> metrics, {
  required WeightRange range,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final valid = metrics.where((m) => m.weightKg > 0).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (valid.isEmpty) return const [];

  var bucketDays = range.bucketDays;
  final days = range.days;
  final cutoff = days == null ? null : at.subtract(Duration(days: days));
  final scoped = cutoff == null
      ? valid
      : valid.where((m) => !m.date.isBefore(cutoff)).toList();
  if (scoped.isEmpty) return const [];

  // "全部"档：跨度很长时用更大的桶，否则一根柱代表一个月读不出变化
  if (range == WeightRange.all) {
    final span = at.difference(scoped.first.date).inDays;
    if (span > 180) {
      bucketDays = 30;
    } else if (span > 60) {
      bucketDays = 14;
    } else {
      bucketDays = 7;
    }
  }

  final buckets = <int, List<BodyMetricEntity>>{};
  for (final m in scoped) {
    final start = range == WeightRange.week
        ? startOfWeek(m.date)
        : _floorToBucket(m.date, bucketDays, anchor: at);
    buckets.putIfAbsent(start.millisecondsSinceEpoch, () => []).add(m);
  }

  final keys = buckets.keys.toList()..sort();
  return [
    for (final key in keys)
      _summarize(
        DateTime.fromMillisecondsSinceEpoch(key),
        bucketDays,
        buckets[key]!,
      ),
  ];
}

/// 周一 00:00（ISO 周：周一是一周第一天，符合中文语境）
DateTime startOfWeek(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1));
}

/// 把日期向下取整到桶起点（以今天为锚，保证最后一桶含今天）
DateTime _floorToBucket(DateTime d, int bucketDays,
    {required DateTime anchor}) {
  final today = DateTime(anchor.year, anchor.month, anchor.day);
  final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  final offset = diff % bucketDays;
  final startDay =
      DateTime(d.year, d.month, d.day).subtract(Duration(days: offset));
  return startDay;
}

WeightBucket _summarize(
    DateTime start, int bucketDays, List<BodyMetricEntity> rows) {
  var sum = 0.0;
  var min = double.infinity;
  for (final r in rows) {
    sum += r.weightKg;
    if (r.weightKg < min) min = r.weightKg;
  }
  return WeightBucket(
    start: start,
    end: start.add(Duration(days: bucketDays)),
    avgKg: sum / rows.length,
    minKg: min,
    count: rows.length,
  );
}

/// 线性回归预测结果
class WeightPrediction {
  /// 每周变化（kg；负数=下降）
  final double slopePerWeek;

  /// 预计多少天后达到目标；null = 不可预测
  final int? daysToTarget;

  const WeightPrediction({required this.slopePerWeek, this.daysToTarget});

  String get direction => slopePerWeek < 0 ? '下降' : '上升';
}

/// 线性回归预测（**纯函数**，从原 `_buildPredictionText` 里搬出来）
///
/// 规则与原来保持一致，避免统计口径变化：
/// - 少于 3 条记录不预测（2 点连线没有统计意义）
/// - 斜率为 0（体重完全没变）不预测
/// - 目标为 null 不预测（用户没设目标就没"达标"这回事）
/// - 预测超过 365 天视为不可信，不展示
WeightPrediction? predictWeightTrend(
  List<BodyMetricEntity> metrics, {
  double? targetKg,
}) {
  final valid = metrics.where((m) => m.weightKg > 0).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (valid.length < 3) return null;

  final n = valid.length;
  double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  for (var i = 0; i < n; i++) {
    final x = i.toDouble();
    final y = valid[i].weightKg;
    sumX += x;
    sumY += y;
    sumXY += x * y;
    sumX2 += x * x;
  }
  final denominator = n * sumX2 - sumX * sumX;
  if (denominator == 0) return null;
  final slope = (n * sumXY - sumX * sumY) / denominator;
  final intercept = (sumY - slope * sumX) / n;

  final slopePerWeek = slope * 7;
  if (targetKg == null || slope == 0) {
    return WeightPrediction(slopePerWeek: slopePerWeek);
  }

  final lastX = (n - 1).toDouble();
  final days = ((targetKg - intercept) / slope - lastX).round();
  if (days <= 0 || days > 365) {
    return WeightPrediction(slopePerWeek: slopePerWeek);
  }
  return WeightPrediction(slopePerWeek: slopePerWeek, daysToTarget: days);
}

/// 本周变化（kg）：**沿用本页既有口径** —— 「7 天前最后一条」到「今天最后一条」
///
/// 注意这与趋势页的口径不一致（那边用的是"本周起点"），这是已知技术债，
/// 本轮不统一（统一要单独决策）。函数放这里只是为了让页面不再手写这段。
double? weekChangeKg(List<BodyMetricEntity> metrics, {DateTime? now}) {
  final valid = metrics.where((m) => m.weightKg > 0).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  if (valid.isEmpty) return null;
  final at = now ?? DateTime.now();
  final cutoff = at.subtract(const Duration(days: 7));
  final older = valid.where((m) => m.date.isBefore(cutoff)).toList();
  if (older.isEmpty) return null;
  return valid.last.weightKg - older.last.weightKg;
}
