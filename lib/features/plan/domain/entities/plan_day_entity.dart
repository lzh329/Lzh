class PlanDayEntity {
  final int id;
  final int planId;
  final int dayOfWeek; // 0=周日, 6=周六
  final int exerciseId;
  final int sortOrder;
  final int targetSets;
  final int? targetReps;
  final double? targetWeightKg;
  final int? targetDurationSec;
  final int restSec;

  const PlanDayEntity({
    required this.id,
    required this.planId,
    required this.dayOfWeek,
    required this.exerciseId,
    this.sortOrder = 0,
    this.targetSets = 3,
    this.targetReps,
    this.targetWeightKg,
    this.targetDurationSec,
    this.restSec = 90,
  });

  static const dayLabels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
}
