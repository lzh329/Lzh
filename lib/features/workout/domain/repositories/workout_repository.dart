import '../entities/workout_entity.dart';

abstract class WorkoutRepository {
  Future<List<WorkoutEntity>> getAll({DateTime? from, DateTime? to});
  Future<WorkoutEntity?> getById(int id);
  Future<WorkoutEntity> createWorkout({
    required DateTime date,
    required String type,
    int? planId,
    String? note,
    int? durationSec,
    required List<NewSetData> sets,
  });
  Future<void> updateWorkout({
    required int id,
    String? note,
    required List<NewSetData> sets,
  });
  Future<void> delete(int id);
}

class NewSetData {
  final int exerciseId;
  final int setNumber;
  final int? reps;
  final double? weightKg;
  final int? durationSec;
  final bool isWarmup;

  const NewSetData({
    required this.exerciseId,
    required this.setNumber,
    this.reps,
    this.weightKg,
    this.durationSec,
    this.isWarmup = false,
  });
}
