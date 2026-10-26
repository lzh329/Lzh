import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';

class ExerciseRepositoryImpl implements ExerciseRepository {
  final AppDatabase _db;
  ExerciseRepositoryImpl(this._db);

  @override
  Future<List<ExerciseEntity>> getAll() async {
    final rows = await (_db.select(_db.exercises)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<ExerciseEntity>> getByCategory(String category) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.category.equals(category))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<ExerciseEntity?> getById(int id) async {
    final row = await (_db.select(_db.exercises)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<ExerciseEntity> create(
      String name, String category, String? muscleGroup) async {
    final id = await _db.into(_db.exercises).insert(ExercisesCompanion.insert(
          name: name,
          category: category,
          muscleGroup: Value(muscleGroup),
          isCustom: const Value(true),
        ));
    return ExerciseEntity(
        id: id,
        name: name,
        category: category,
        muscleGroup: muscleGroup,
        isCustom: true);
  }

  @override
  Future<void> update(ExerciseEntity exercise) async {
    await (_db.update(_db.exercises)..where((t) => t.id.equals(exercise.id)))
        .write(ExercisesCompanion(
      name: Value(exercise.name),
      category: Value(exercise.category),
      muscleGroup: Value(exercise.muscleGroup),
    ));
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.exercises)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<List<ExerciseEntity>> search(String query) async {
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.name.like('%$query%'))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> saveDefaults(int id,
      {int? defaultReps,
      double? defaultWeightKg,
      int? defaultDurationSec}) async {
    await (_db.update(_db.exercises)..where((t) => t.id.equals(id)))
        .write(ExercisesCompanion(
      defaultReps:
          defaultReps != null ? Value(defaultReps) : const Value.absent(),
      defaultWeightKg: defaultWeightKg != null
          ? Value(defaultWeightKg)
          : const Value.absent(),
      defaultDurationSec: defaultDurationSec != null
          ? Value(defaultDurationSec)
          : const Value.absent(),
    ));
  }

  ExerciseEntity _toEntity(Exercise row) => ExerciseEntity(
        id: row.id,
        name: row.name,
        category: row.category,
        muscleGroup: row.muscleGroup,
        isCustom: row.isCustom,
        defaultReps: row.defaultReps,
        defaultWeightKg: row.defaultWeightKg,
        defaultDurationSec: row.defaultDurationSec,
      );
}
