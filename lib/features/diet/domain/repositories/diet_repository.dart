import '../entities/diet_entity.dart';

abstract class DietRepository {
  // 食物库
  Future<List<FoodLibraryEntity>> searchFoods(
      {String? query, String? category});
  Future<FoodLibraryEntity?> getFoodById(int id);

  // 饮食记录
  Future<List<FoodLogEntity>> getLogsByDate(DateTime date);
  Future<void> addLog({
    required DateTime date,
    required int foodId,
    required double grams,
    required String mealType,
  });
  Future<void> deleteLog(int id);

  // 每日汇总
  Future<double> getDailyCalories(DateTime date);
}
