import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/diet/domain/entities/diet_entity.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';

class DietRepositoryImpl implements DietRepository {
  final AppDatabase _db;

  DietRepositoryImpl(this._db);

  @override
  Future<List<FoodLibraryEntity>> searchFoods(
      {String? query, String? category}) async {
    var stmt = _db.select(_db.foodLibrary);
    if (query != null && query.isNotEmpty) {
      stmt = stmt..where((t) => t.name.like('%$query%'));
    }
    if (category != null) {
      stmt = stmt..where((t) => t.category.equals(category));
    }
    stmt = stmt..orderBy([(t) => OrderingTerm(expression: t.name)]);
    final rows = await stmt.get();
    return rows
        .map((r) => FoodLibraryEntity(
              id: r.id,
              name: r.name,
              caloriesPer100g: r.caloriesPer100g,
              proteinPer100g: r.proteinPer100g,
              fatPer100g: r.fatPer100g,
              carbsPer100g: r.carbsPer100g,
              category: r.category,
              isCustom: r.isCustom,
            ))
        .toList();
  }

  @override
  Future<FoodLibraryEntity?> getFoodById(int id) async {
    final row = await (_db.select(_db.foodLibrary)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return FoodLibraryEntity(
      id: row.id,
      name: row.name,
      caloriesPer100g: row.caloriesPer100g,
      proteinPer100g: row.proteinPer100g,
      fatPer100g: row.fatPer100g,
      carbsPer100g: row.carbsPer100g,
      category: row.category,
      isCustom: row.isCustom,
    );
  }

  @override
  Future<List<FoodLogEntity>> getLogsByDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = _db.select(_db.foodLog).join([
      innerJoin(
          _db.foodLibrary, _db.foodLibrary.id.equalsExp(_db.foodLog.foodId)),
    ])
      ..where(_db.foodLog.date.isBiggerOrEqualValue(startOfDay) &
          _db.foodLog.date.isSmallerThanValue(endOfDay))
      ..orderBy([OrderingTerm(expression: _db.foodLog.date)]);

    final rows = await query.get();
    return rows.map((r) {
      final log = r.readTable(_db.foodLog);
      final food = r.readTable(_db.foodLibrary);
      return FoodLogEntity(
        id: log.id,
        date: log.date,
        foodId: log.foodId,
        grams: log.grams,
        mealType: log.mealType,
        foodName: food.name,
        caloriesPer100g: food.caloriesPer100g,
      );
    }).toList();
  }

  @override
  Future<void> addLog({
    required DateTime date,
    required int foodId,
    required double grams,
    required String mealType,
  }) async {
    await _db.into(_db.foodLog).insert(FoodLogCompanion(
          date: Value(date),
          foodId: Value(foodId),
          grams: Value(grams),
          mealType: Value(mealType),
        ));
  }

  @override
  Future<void> deleteLog(int id) async {
    await (_db.delete(_db.foodLog)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<double> getDailyCalories(DateTime date) async {
    final logs = await getLogsByDate(date);
    double total = 0;
    for (final l in logs) {
      total += l.totalCalories;
    }
    return total;
  }
}
