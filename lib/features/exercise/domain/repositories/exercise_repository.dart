import '../entities/exercise.dart';

abstract class ExerciseRepository {
  Future<List<ExerciseEntity>> getAll();
  Future<List<ExerciseEntity>> getByCategory(String category);
  Future<ExerciseEntity?> getById(int id);
  Future<ExerciseEntity> create(
      String name, String category, String? muscleGroup);
  Future<void> update(ExerciseEntity exercise);
  Future<void> delete(int id);
  Future<List<ExerciseEntity>> search(String query);
  Future<void> saveDefaults(int id,
      {int? defaultReps, double? defaultWeightKg, int? defaultDurationSec});
}
