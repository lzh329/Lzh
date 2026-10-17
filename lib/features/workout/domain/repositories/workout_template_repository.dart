import '../entities/workout_template_entity.dart';

abstract class WorkoutTemplateRepository {
  Future<List<WorkoutTemplateEntity>> getAll();
  Future<WorkoutTemplateEntity?> getById(int id);

  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  });

  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  });

  Future<void> delete(int id);
}

/// 模板动作输入
class TemplateItemInput {
  final int exerciseId;
  final int targetSets;
  final int? targetReps;
  final int? targetDurationSec;

  const TemplateItemInput({
    required this.exerciseId,
    this.targetSets = 3,
    this.targetReps,
    this.targetDurationSec,
  });
}
