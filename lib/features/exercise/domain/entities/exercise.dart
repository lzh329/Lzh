/// 训练动作实体
class ExerciseEntity {
  final int id;
  final String name;
  final String category;
  final String? muscleGroup;
  final bool isCustom;
  final int? defaultReps;
  final double? defaultWeightKg;
  final int? defaultDurationSec;

  const ExerciseEntity({
    required this.id,
    required this.name,
    required this.category,
    this.muscleGroup,
    this.isCustom = false,
    this.defaultReps,
    this.defaultWeightKg,
    this.defaultDurationSec,
  });
}
