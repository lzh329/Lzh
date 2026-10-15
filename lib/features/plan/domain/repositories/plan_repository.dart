import '../entities/plan_entity.dart';

abstract class PlanRepository {
  Future<List<PlanEntity>> getAll();
  Future<PlanEntity?> getById(int id);
  Future<PlanEntity> create(String name, {String? note});
  Future<void> updateName(int id, String name, {String? note});
  Future<void> delete(int id);
  Future<void> toggleActive(int id, bool isActive);
  Future<void> saveDays(int planId, List<PlanDayInput> days);
}

class PlanDayInput {
  final int? id;
  final int dayOfWeek;
  final int exerciseId;
  final int sortOrder;
  final int targetSets;
  final int? targetReps;
  final double? targetWeightKg;
  final int? targetDurationSec;
  final int restSec;

  const PlanDayInput({
    this.id,
    required this.dayOfWeek,
    required this.exerciseId,
    this.sortOrder = 0,
    this.targetSets = 3,
    this.targetReps,
    this.targetWeightKg,
    this.targetDurationSec,
    this.restSec = 90,
  });
}
