import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

class WorkoutTemplateRepositoryImpl implements WorkoutTemplateRepository {
  final AppDatabase db;

  WorkoutTemplateRepositoryImpl(this.db);

  @override
  Future<List<WorkoutTemplateEntity>> getAll() async {
    final templates = await (db.select(db.workoutTemplates)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.isRecommended,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.asc,
                ),
          ]))
        .get();
    if (templates.isEmpty) return const [];

    final items = await db.select(db.workoutTemplateExercises).get();
    final exercises = await db.select(db.exercises).get();
    final exById = {for (final e in exercises) e.id: e};

    return templates.map((t) {
      final its = items.where((i) => i.templateId == t.id).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return WorkoutTemplateEntity(
        id: t.id,
        name: t.name,
        difficulty: t.difficulty,
        focus: t.focus,
        minutes: t.minutes,
        description: t.description,
        accentKey: t.accentKey,
        isRecommended: t.isRecommended,
        items: its
            .map((i) => WorkoutTemplateItemEntity(
                  id: i.id,
                  templateId: i.templateId,
                  exerciseId: i.exerciseId,
                  exerciseName: exById[i.exerciseId]?.name ?? '未知动作',
                  category: exById[i.exerciseId]?.category ?? 'bodyweight',
                  targetSets: i.targetSets,
                  targetReps: i.targetReps,
                  targetDurationSec: i.targetDurationSec,
                ))
            .toList(),
      );
    }).toList();
  }

  @override
  Future<WorkoutTemplateEntity?> getById(int id) async {
    final all = await getAll();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    return db.transaction(() async {
      final id = await db.into(db.workoutTemplates).insert(
            WorkoutTemplatesCompanion.insert(
              name: name,
              difficulty: difficulty,
              focus: focus,
              minutes: Value(minutes),
              description: Value(description),
              isRecommended: const Value(false),
            ),
          );
      await _insertItems(id, items);
      return id;
    });
  }

  @override
  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    await db.transaction(() async {
      await (db.update(db.workoutTemplates)..where((t) => t.id.equals(id)))
          .write(WorkoutTemplatesCompanion(
        name: Value(name),
        difficulty: Value(difficulty),
        focus: Value(focus),
        minutes: Value(minutes),
        description: Value(description),
      ));
      await (db.delete(db.workoutTemplateExercises)
            ..where((i) => i.templateId.equals(id)))
          .go();
      await _insertItems(id, items);
    });
  }

  @override
  Future<void> delete(int id) async {
    await db.transaction(() async {
      await (db.delete(db.workoutTemplateExercises)
            ..where((i) => i.templateId.equals(id)))
          .go();
      await (db.delete(db.workoutTemplates)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> _insertItems(int templateId, List<TemplateItemInput> items) async {
    var order = 0;
    for (final it in items) {
      await db.into(db.workoutTemplateExercises).insert(
            WorkoutTemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: it.exerciseId,
              sortOrder: Value(order++),
              targetSets: Value(it.targetSets),
              targetReps: Value(it.targetReps),
              targetDurationSec: Value(it.targetDurationSec),
            ),
          );
    }
  }
}
