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
  /// 当日热量。
  ///
  /// **薄包装**：实现必须直接返回 [getDailyNutrition]().calories，
  /// 不许自带 SQL —— 全 App 只有一个方法产出口径。
  Future<double> getDailyCalories(DateTime date);

  /// 当日营养口径（热量 + 三态宏量），**一条 SQL** 出全部。
  Future<DailyNutrition> getDailyNutrition(DateTime date);

  // AI 教练记录用：按名称精确查食物、新建自定义食物
  Future<FoodLibraryEntity?> findFoodByName(String name);

  /// 新建自定义食物。
  ///
  /// 三大营养素**可选且默认为 null**：null = 未知（UI 显示「—」），
  /// 只有模型真的估出来才传值 —— 绝不许用 0 冒充"没估出来"。
  Future<int> addCustomFood({
    required String name,
    required double caloriesPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    String category = 'other',
  });
}
