import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';

class BodyMetricRepositoryImpl implements BodyMetricRepository {
  final AppDatabase _db;
  BodyMetricRepositoryImpl(this._db);

  @override
  Future<List<BodyMetricEntity>> getAll({DateTime? from, DateTime? to}) async {
    var query = _db.select(_db.bodyMetrics)
      ..orderBy([(t) => OrderingTerm.asc(t.date)]);

    if (from != null) {
      query = query..where((t) => t.date.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      final nextDay = to.add(const Duration(days: 1));
      query = query..where((t) => t.date.isSmallerThanValue(nextDay));
    }

    final rows = await query.get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<BodyMetricEntity?> getLatest() async {
    final row = await (_db.select(_db.bodyMetrics)
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(1))
        .getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
  Future<BodyMetricEntity> create({
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  }) async {
    final id =
        await _db.into(_db.bodyMetrics).insert(BodyMetricsCompanion.insert(
              date: date,
              weightKg: weightKg,
              waistCm: Value(waistCm),
              hipCm: Value(hipCm),
              chestCm: Value(chestCm),
              note: Value(note),
            ));

    return BodyMetricEntity(
      id: id,
      date: date,
      weightKg: weightKg,
      waistCm: waistCm,
      hipCm: hipCm,
      chestCm: chestCm,
      note: note,
    );
  }

  @override
  Future<void> update({
    required int id,
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  }) async {
    await (_db.update(_db.bodyMetrics)..where((t) => t.id.equals(id)))
        .write(BodyMetricsCompanion(
      date: Value(date),
      weightKg: Value(weightKg),
      waistCm: waistCm != null ? Value(waistCm) : const Value.absent(),
      hipCm: hipCm != null ? Value(hipCm) : const Value.absent(),
      chestCm: chestCm != null ? Value(chestCm) : const Value.absent(),
      note: note != null ? Value(note) : const Value.absent(),
    ));
  }

  @override
  Future<void> delete(int id) async {
    await (_db.delete(_db.bodyMetrics)..where((t) => t.id.equals(id))).go();
  }

  BodyMetricEntity _toEntity(BodyMetric row) => BodyMetricEntity(
        id: row.id,
        date: row.date,
        weightKg: row.weightKg,
        waistCm: row.waistCm,
        hipCm: row.hipCm,
        chestCm: row.chestCm,
        note: row.note,
      );
}
