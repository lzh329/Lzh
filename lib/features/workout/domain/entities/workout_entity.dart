class WorkoutEntity {
  final int id;
  final DateTime date;
  final String type;
  final int? planId;
  final String? note;
  final int? durationSec;
  final List<WorkoutSetEntity> sets;

  const WorkoutEntity({
    required this.id,
    required this.date,
    required this.type,
    this.planId,
    this.note,
    this.durationSec,
    this.sets = const [],
  });

  int get totalSets => sets.length;
  int get completedSets => sets.where((s) => s.isCompleted).length;
}

class WorkoutSetEntity {
  final int id;
  final int workoutId;
  final int exerciseId;
  final int setNumber;
  final int? reps;
  final double? weightKg;
  final int? durationSec;
  final bool isWarmup;
  final bool isCompleted;

  const WorkoutSetEntity({
    required this.id,
    required this.workoutId,
    required this.exerciseId,
    required this.setNumber,
    this.reps,
    this.weightKg,
    this.durationSec,
    this.isWarmup = false,
    this.isCompleted = true,
  });
}
