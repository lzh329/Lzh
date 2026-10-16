import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/weight_analysis.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 趋势页聚合数据
class TrendsData {
  final List<BodyMetricEntity> metrics; // 按日期升序
  final double? targetJin;
  final int daysRecorded;
  final int workoutDays; // 累计训练天数（去重）
  final int weekWorkoutDays; // 本周训练天数
  final int photoCount;
  final double? weekChangeJin; // 本周变化（负 = 下降）
  final int? daysToTarget;
  final DateTime? targetDate;
  final double? todayCalories;

  const TrendsData({
    this.metrics = const [],
    this.targetJin,
    this.daysRecorded = 0,
    this.workoutDays = 0,
    this.weekWorkoutDays = 0,
    this.photoCount = 0,
    this.weekChangeJin,
    this.daysToTarget,
    this.targetDate,
    this.todayCalories,
  });

  bool get hasWeight => metrics.isNotEmpty;

  DateTime? get startDate => metrics.isNotEmpty ? metrics.first.date : null;
  DateTime? get latestDate => metrics.isNotEmpty ? metrics.last.date : null;
  double? get startJin => metrics.isNotEmpty ? metrics.first.weightKg * 2 : null;
  double? get currentJin => metrics.isNotEmpty ? metrics.last.weightKg * 2 : null;

  /// 距目标还差多少斤（正 = 还差这么多）
  double? get remainingJin => (currentJin != null && targetJin != null)
      ? currentJin! - targetJin!
      : null;

  /// 累计减重（正 = 减了这么多）
  double? get totalLossJin =>
      (startJin != null && currentJin != null && metrics.length >= 2)
          ? startJin! - currentJin!
          : null;
}

/// 趋势页数据 Provider
final trendsDataProvider = FutureProvider<TrendsData>((ref) async {
  final bodyRepo = ref.watch(bodyMetricRepoProvider);
  final workoutRepo = ref.watch(workoutRepoProvider);
  final photoRepo = ref.watch(photoRepoProvider);
  final dietRepo = ref.watch(dietRepoProvider);
  final settings = await ref.watch(userSettingsProvider.future);

  final metrics = [...await bodyRepo.getAll()]
    ..sort((a, b) => a.date.compareTo(b.date));
  final workouts = await workoutRepo.getAll();
  final photos = await photoRepo.getAll();

  final targetKg = settings?.targetWeightKg;

  // 本周变化：本周第一条 → 最新
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final weekMetrics =
      metrics.where((m) => !m.date.isBefore(monday)).toList();
  double? weekChangeJin;
  if (weekMetrics.length >= 2) {
    weekChangeJin = (metrics.last.weightKg - weekMetrics.first.weightKg) * 2;
  }

  final todayCalories = await dietRepo.getDailyCalories(now);
  final weekWorkoutDays = workouts
      .where((w) => !w.date.isBefore(monday))
      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
      .toSet()
      .length;

  return TrendsData(
    metrics: metrics,
    targetJin: targetKg != null ? targetKg * 2 : null,
    daysRecorded: metrics
        .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
        .toSet()
        .length,
    workoutDays: workouts
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet()
        .length,
    weekWorkoutDays: weekWorkoutDays,
    photoCount: photos.length,
    weekChangeJin: weekChangeJin,
    daysToTarget: WeightAnalysis.predictDaysToTarget(metrics, targetKg),
    targetDate: WeightAnalysis.predictTargetDate(metrics, targetKg),
    todayCalories: todayCalories > 0 ? todayCalories : null,
  );
});
