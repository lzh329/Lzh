import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

class WorkoutRepositoryImpl implements WorkoutRepository {
  final AppDatabase _db;
  WorkoutRepositoryImpl(this._db);

  @override
  Future<List<WorkoutEntity>> getAll({DateTime? from, DateTime? to}) async {
    var query = _db.select(_db.workouts)
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);

    if (from != null) {
      query = query..where((t) => t.date.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      final nextDay = to.add(const Duration(days: 1));
      query = query..where((t) => t.date.isSmallerThanValue(nextDay));
    }

    final workoutRows = await query.get();
    final workouts = <WorkoutEntity>[];

    for (final row in workoutRows) {
      final sets = await _getSets(row.id);
      workouts.add(WorkoutEntity(
        id: row.id,
        date: row.date,
        type: row.type,
        planId: row.planId,
        note: row.note,
        durationSec: row.durationSec,
        sets: sets,
      ));
    }
    return workouts;
  }

  @override
  Future<WorkoutEntity?> getById(int id) async {
    final row = await (_db.select(_db.workouts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;

    final sets = await _getSets(row.id);
    return WorkoutEntity(
      id: row.id,
      date: row.date,
      type: row.type,
      planId: row.planId,
      note: row.note,
      durationSec: row.durationSec,
      sets: sets,
    );
  }

  @override
  Future<WorkoutEntity> createWorkout({
    required DateTime date,
    required String type,
    int? planId,
    String? note,
    int? durationSec,
    required List<NewSetData> sets,
  }) async {
    final workoutId = await _db.transaction(() async {
      final id = await _db.into(_db.workouts).insert(WorkoutsCompanion.insert(
            date: date,
            type: type,
            planId: Value(planId),
            note: Value(note),
            durationSec: Value(durationSec),
          ));

      for (final set in sets) {
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion.insert(
              workoutId: id,
              exerciseId: set.exerciseId,
              setNumber: set.setNumber,
              reps: Value(set.reps),
              weightKg: Value(set.weightKg),
              durationSec: Value(set.durationSec),
              isWarmup: Value(set.isWarmup),
            ));
      }
      return id;
    });

    return (await getById(workoutId))!;
  }

  @override
  Future<void> updateWorkout({
    required int id,
    String? note,
    required List<NewSetData> sets,
  }) async {
    await _db.transaction(() async {
      // 更新备注
      if (note != null) {
        await (_db.update(_db.workouts)..where((t) => t.id.equals(id)))
            .write(WorkoutsCompanion(note: Value(note)));
      }
      // 删除旧组
      await (_db.delete(_db.workoutSets)..where((t) => t.workoutId.equals(id)))
          .go();
      // 插入新组
      for (final s in sets) {
        await _db.into(_db.workoutSets).insert(WorkoutSetsCompanion(
              workoutId: Value(id),
              exerciseId: Value(s.exerciseId),
              setNumber: Value(s.setNumber),
              reps: Value.absentIfNull(s.reps),
              weightKg: Value.absentIfNull(s.weightKg),
              durationSec: Value.absentIfNull(s.durationSec),
              isWarmup: Value(s.isWarmup),
            ));
      }
    });
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.workouts)..where((t) => t.id.equals(id))).go();
  }

  Future<List<WorkoutSetEntity>> _getSets(int workoutId) async {
    final rows = await (_db.select(_db.workoutSets)
          ..where((t) => t.workoutId.equals(workoutId))
          ..orderBy([(t) => OrderingTerm.asc(t.setNumber)]))
        .get();

    return rows
        .map((r) => WorkoutSetEntity(
              id: r.id,
              workoutId: r.workoutId,
              exerciseId: r.exerciseId,
              setNumber: r.setNumber,
              reps: r.reps,
              weightKg: r.weightKg,
              durationSec: r.durationSec,
              isWarmup: r.isWarmup,
              isCompleted: r.isCompleted,
            ))
        .toList();
  }
}
