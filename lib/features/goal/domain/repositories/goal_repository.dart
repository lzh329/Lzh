import '../entities/goal_entity.dart';

abstract class GoalRepository {
  Future<List<GoalEntity>> getAll();
  Future<GoalEntity?> getById(int id);
  Future<GoalEntity> create({
    required String type,
    String? category,
    required double targetValue,
    required DateTime startDate,
    DateTime? endDate,
  });
  Future<void> updateProgress(int id, double currentValue);
  Future<void> complete(int id);
  Future<void> delete(int id);
}
