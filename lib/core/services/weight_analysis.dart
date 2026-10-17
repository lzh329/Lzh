import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 体重趋势分析 —— 纯计算逻辑（无 Flutter 依赖）
class WeightAnalysis {
  WeightAnalysis._();

  /// 线性回归预测距目标体重还有多少天。
  /// 记录不足 3 条、无目标或无法预测时返回 null。
  static int? predictDaysToTarget(
    List<BodyMetricEntity> metrics,
    double? targetKg,
  ) {
    if (metrics.length < 3 || targetKg == null) return null;

    final sorted = [...metrics]..sort((a, b) => a.date.compareTo(b.date));
    final n = sorted.length;

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = sorted[i].weightKg;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return null;

    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    // 体重基本不变时无法预测
    if (slope.abs() < 0.001) return null;

    final lastX = (n - 1).toDouble();
    final days = ((targetKg - intercept) / slope - lastX).round();

    if (days <= 0 || days > 365) return null;
    return days;
  }

  /// 预测达到目标体重的日期
  static DateTime? predictTargetDate(
    List<BodyMetricEntity> metrics,
    double? targetKg,
  ) {
    final days = predictDaysToTarget(metrics, targetKg);
    if (days == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  /// 目标进度（0~1）：从起始体重走向目标的完成度
  ///
  /// 无起始基准时按"距目标 20 斤 = 满环"的相对进度兜底。
  static double targetProgress({
    required double? startJin,
    required double? currentJin,
    required double? targetJin,
  }) {
    if (currentJin == null || targetJin == null) return 0;
    if (currentJin <= targetJin) return 1;

    final start = startJin;
    if (start == null || start <= targetJin) {
      final span = (currentJin - targetJin) > 20.0
          ? (currentJin - targetJin)
          : 20.0;
      return ((span - (currentJin - targetJin)) / span).clamp(0.0, 1.0);
    }
    return ((start - currentJin) / (start - targetJin)).clamp(0.0, 1.0);
  }
}
