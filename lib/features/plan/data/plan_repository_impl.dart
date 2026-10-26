import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';

class PlanRepositoryImpl implements PlanRepository {
  final AppDatabase _db;
  PlanRepositoryImpl(this._db);

  @override
  Future<List<PlanEntity>> getAll() async {
    final planRows = await (_db.select(_db.plans)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    final plans = <PlanEntity>[];
    for (final row in planRows) {
      final days = await _getDays(row.id);
      plans.add(PlanEntity(
        id: row.id,
        name: row.name,
        note: row.note,
        isActive: row.isActive,
        days: days,
      ));
    }
    return plans;
  }

  @override
  Future<PlanEntity?> getById(int id) async {
    final row = await (_db.select(_db.plans)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;

    final days = await _getDays(row.id);
    return PlanEntity(
      id: row.id,
      name: row.name,
      note: row.note,
      isActive: row.isActive,
      days: days,
    );
  }

  @override
  Future<PlanEntity> create(String name, {String? note}) async {
    final id = await _db.into(_db.plans).insert(PlansCompanion.insert(
          name: name,
          note: Value(note),
        ));
    return PlanEntity(id: id, name: name, note: note);
  }

  @override
  Future<void> updateName(int id, String name, {String? note}) async {
    await (_db.update(_db.plans)..where((t) => t.id.equals(id)))
        .write(PlansCompanion(name: Value(name), note: Value(note)));
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.plans)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> toggleActive(int id, bool isActive) async {
    await (_db.update(_db.plans)..where((t) => t.id.equals(id)))
        .write(PlansCompanion(isActive: Value(isActive)));
  }

  @override
  Future<void> saveDays(int planId, List<PlanDayInput> days) async {
    await _db.transaction(() async {
      // 先删除旧数据
      await (_db.delete(_db.planDays)..where((t) => t.planId.equals(planId)))
          .go();

      // 插入新数据
      for (final d in days) {
        await _db.into(_db.planDays).insert(PlanDaysCompanion.insert(
              planId: planId,
              dayOfWeek: d.dayOfWeek,
              exerciseId: d.exerciseId,
              sortOrder: Value(d.sortOrder),
              targetSets: Value(d.targetSets),
              targetReps: Value(d.targetReps),
              targetWeightKg: Value(d.targetWeightKg),
              targetDurationSec: Value(d.targetDurationSec),
              restSec: Value(d.restSec),
            ));
      }
    });
  }

  Future<List<PlanDayEntity>> _getDays(int planId) async {
    final rows = await (_db.select(_db.planDays)
          ..where((t) => t.planId.equals(planId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.dayOfWeek),
            (t) => OrderingTerm.asc(t.sortOrder)
          ]))
        .get();

    return rows
        .map((r) => PlanDayEntity(
              id: r.id,
              planId: r.planId,
              dayOfWeek: r.dayOfWeek,
              exerciseId: r.exerciseId,
              sortOrder: r.sortOrder,
              targetSets: r.targetSets,
              targetReps: r.targetReps,
              targetWeightKg: r.targetWeightKg,
              targetDurationSec: r.targetDurationSec,
              restSec: r.restSec,
            ))
        .toList();
  }
}
