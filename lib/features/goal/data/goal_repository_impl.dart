import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';

class GoalRepositoryImpl implements GoalRepository {
  final AppDatabase _db;

  GoalRepositoryImpl(this._db);

  @override
  Future<List<GoalEntity>> getAll() async {
    final rows = await (_db.select(_db.goals)
      ..orderBy([(t) => OrderingTerm(expression: t.isCompleted), (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
      .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<GoalEntity?> getById(int id) async {
    final row = await (_db.select(_db.goals)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<GoalEntity> create({
    required String type,
    String? category,
    required double targetValue,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final id = await _db.into(_db.goals).insert(GoalsCompanion(
      type: Value(type),
      category: Value.absentIfNull(category),
      targetValue: Value(targetValue),
      startDate: Value(startDate),
      endDate: Value.absentIfNull(endDate),
    ));
    return (await getById(id))!;
  }

  @override
  Future<void> updateProgress(int id, double currentValue) async {
    await (_db.update(_db.goals)..where((t) => t.id.equals(id))).write(GoalsCompanion(currentValue: Value(currentValue)));
    // Auto-complete if target reached
    final goal = await getById(id);
    if (goal != null && goal.currentValue >= goal.targetValue && !goal.isCompleted) {
      await complete(id);
    }
  }

  @override
  Future<void> complete(int id) async {
    await (_db.update(_db.goals)..where((t) => t.id.equals(id))).write(GoalsCompanion(isCompleted: const Value(true)));
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.goals)..where((t) => t.id.equals(id))).go();
  }

  GoalEntity _toEntity(Goal row) => GoalEntity(
    id: row.id,
    type: row.type,
    category: row.category,
    targetValue: row.targetValue,
    currentValue: row.currentValue,
    startDate: row.startDate,
    endDate: row.endDate,
    isCompleted: row.isCompleted,
    createdAt: row.createdAt,
  );
}
