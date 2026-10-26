import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';

class WaterLogEntry {
  final int id;
  final DateTime date;
  final int cups;
  const WaterLogEntry(
      {required this.id, required this.date, required this.cups});
}

abstract class WaterRepository {
  Future<int> getTodayCups();
  Future<void> incrementCup();
  Future<void> decrementCup();
  Future<List<WaterLogEntry>> getHistory();
}

class WaterRepositoryImpl implements WaterRepository {
  final AppDatabase _db;

  WaterRepositoryImpl(this._db);

  @override
  Future<int> getTodayCups() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    final rows = await (_db.select(_db.waterLog)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .get();

    int total = 0;
    for (final r in rows) {
      total += r.cups;
    }
    return total;
  }

  @override
  Future<void> incrementCup() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    final existing = await (_db.select(_db.waterLog)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.waterLog)..where((t) => t.id.equals(existing.id)))
          .write(WaterLogCompanion(cups: Value(existing.cups + 1)));
    } else {
      await _db.into(_db.waterLog).insert(WaterLogCompanion(
            date: Value(today),
            cups: const Value(1),
          ));
    }
  }

  @override
  Future<void> decrementCup() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));

    final existing = await (_db.select(_db.waterLog)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end)))
        .getSingleOrNull();

    if (existing != null && existing.cups > 0) {
      await (_db.update(_db.waterLog)..where((t) => t.id.equals(existing.id)))
          .write(WaterLogCompanion(cups: Value(existing.cups - 1)));
    }
  }

  @override
  Future<List<WaterLogEntry>> getHistory() async {
    final rows = await (_db.select(_db.waterLog)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
    return rows
        .map((r) => WaterLogEntry(id: r.id, date: r.date, cups: r.cups))
        .toList();
  }
}
