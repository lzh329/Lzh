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
        proteinPer100g: food.proteinPer100g,
        fatPer100g: food.fatPer100g,
        carbsPer100g: food.carbsPer100g,
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
    // 薄包装：口径只有 getDailyNutrition 一处产出，不许在这里再写一遍求和
    return (await getDailyNutrition(date)).calories;
  }

  @override
  Future<DailyNutrition> getDailyNutrition(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // **一条 SQL** 出全部口径。
    //
    // 三处细节都是有意为之：
    // 1. 宏量用 `SUM(CASE WHEN ... IS NOT NULL THEN ... END)`：全缺时 SUM 为
    //    NULL（不是 0）—— 正好让"未知"和"真的是 0"在类型上就分开；
    // 2. `macroLogCount` 要求**三项齐备**才算一条有营养数据，
    //    和 `FoodLogEntity.hasMacros` 同一个判据；
    // 3. 热量用 COALESCE 兜 0：热量永远能算出来，是"缺失"对不上的量。
    final rows = await _db.customSelect(
      '''
      SELECT
        COALESCE(SUM(fl.grams / 100.0 * fo.calories_per100g), 0) AS calories,
        SUM(CASE WHEN fo.protein_per100g IS NOT NULL
                 THEN fl.grams / 100.0 * fo.protein_per100g END) AS protein_g,
        SUM(CASE WHEN fo.fat_per100g IS NOT NULL
                 THEN fl.grams / 100.0 * fo.fat_per100g END) AS fat_g,
        SUM(CASE WHEN fo.carbs_per100g IS NOT NULL
                 THEN fl.grams / 100.0 * fo.carbs_per100g END) AS carbs_g,
        COUNT(*) AS log_count,
        SUM(CASE WHEN fo.protein_per100g IS NOT NULL
                  AND fo.fat_per100g IS NOT NULL
                  AND fo.carbs_per100g IS NOT NULL
                 THEN 1 ELSE 0 END) AS macro_log_count
      FROM food_log fl
      INNER JOIN food_library fo ON fo.id = fl.food_id
      WHERE fl.date >= ? AND fl.date < ?
      ''',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
    ).get();

    if (rows.isEmpty) return DailyNutrition.empty;
    final row = rows.first;
    final logCount = (row.data['log_count'] as num?)?.toInt() ?? 0;
    if (logCount == 0) return DailyNutrition.empty;

    final macroLogCount = (row.data['macro_log_count'] as num?)?.toInt() ?? 0;
    final coverage = macroLogCount / logCount;

    // coverage == 0 → 宏量必须为 null（而不是 0）：0 代表"真的是 0"
    return DailyNutrition(
      calories: (row.data['calories'] as num?)?.toDouble() ?? 0,
      proteinG:
          coverage == 0 ? null : (row.data['protein_g'] as num?)?.toDouble(),
      fatG: coverage == 0 ? null : (row.data['fat_g'] as num?)?.toDouble(),
      carbsG: coverage == 0 ? null : (row.data['carbs_g'] as num?)?.toDouble(),
      macroCoverage: coverage,
      logCount: logCount,
      macroLogCount: macroLogCount,
    );
  }

  @override
  Future<FoodLibraryEntity?> findFoodByName(String name) async {
    final row = await (_db.select(_db.foodLibrary)
          ..where((t) => t.name.equals(name.trim()))
          ..limit(1))
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
  Future<int> addCustomFood({
    required String name,
    required double caloriesPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    String category = 'other',
  }) async {
    // 宏量不传就写 NULL（= 未知），绝不兜 0 —— 0 会被当成"算过了、结果是 0"
    return _db.into(_db.foodLibrary).insert(FoodLibraryCompanion.insert(
          name: name.trim(),
          caloriesPer100g: caloriesPer100g,
          proteinPer100g: Value(proteinPer100g),
          fatPer100g: Value(fatPer100g),
          carbsPer100g: Value(carbsPer100g),
          category: category,
          isCustom: const Value(true),
        ));
  }
}
