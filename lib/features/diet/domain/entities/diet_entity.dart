class FoodLibraryEntity {
  final int id;
  final String name;
  final double caloriesPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;
  final String category;
  final bool isCustom;

  const FoodLibraryEntity({
    required this.id,
    required this.name,
    required this.caloriesPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.carbsPer100g,
    required this.category,
    this.isCustom = false,
  });

  static const categoryLabels = {
    'staple': '主食',
    'meat': '肉类',
    'vegetable': '蔬菜',
    'fruit': '水果',
    'snack': '零食',
    'drink': '饮品',
    'other': '其他',
  };
}

class FoodLogEntity {
  final int id;
  final DateTime date;
  final int foodId;
  final double grams;
  final String mealType;

  /// 关联的食物信息（JOIN 查询时填充）
  final String? foodName;
  final double? caloriesPer100g;

  /// 关联食物的三大营养素（每 100g）。**必须由 JOIN 带出**，
  /// 不允许调用方拿 foodId 再查一次 —— 那会让"3 条记录"变成 4 次查询，
  /// 也会让不同页面各查各的、口径重新分叉。
  ///
  /// 三者同时为 null 表示"这条记录没有营养数据"（老数据 / AI 没给），
  /// **绝不能用 0 冒充缺失**。
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;

  const FoodLogEntity({
    required this.id,
    required this.date,
    required this.foodId,
    required this.grams,
    required this.mealType,
    this.foodName,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.carbsPer100g,
  });

  /// 这条记录是否带营养数据（三项齐备才算）
  bool get hasMacros =>
      proteinPer100g != null && fatPer100g != null && carbsPer100g != null;

  /// 计算该记录的热量 = 克数 / 100 * 每百克热量
  double get totalCalories {
    if (caloriesPer100g == null) return 0;
    return grams / 100 * caloriesPer100g!;
  }

  static const mealTypeLabels = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
  };
}

/// 当日营养口径 —— **全 App 唯一的当日营养来源**。
///
/// 设计要点（改之前先读）：
/// 1. `calories` 永远不为 null，无记录就是 0（热量是"能算出来"的量）。
/// 2. 宏量三兄弟 `null` = **未知**，`0` = **真的是 0**。两者不能混：
///    3 条记录里 2 条缺宏量时，把剩下 1 条加起来会得到一个"看起来权威的
///    偏低数字"，比显示「—」更糟。
/// 3. `macroCoverage` = 有宏量的条数 / 总条数（无记录为 0），
///    用来在 UI 上区分三态：全有 / 部分有 / 全缺。
class DailyNutrition {
  /// 当日总热量（无记录为 0，永不 null）
  final double calories;

  /// 已知部分的宏量之和；[macroCoverage] == 0 时**必须为 null**
  final double? proteinG;
  final double? fatG;
  final double? carbsG;

  /// 有宏量的记录条数 / 总记录条数（无记录为 0）
  final double macroCoverage;

  /// 当日记录条数
  final int logCount;

  /// 有宏量数据的记录条数
  final int macroLogCount;

  const DailyNutrition({
    required this.calories,
    required this.proteinG,
    required this.fatG,
    required this.carbsG,
    required this.macroCoverage,
    required this.logCount,
    required this.macroLogCount,
  });

  /// 空日
  static const empty = DailyNutrition(
    calories: 0,
    proteinG: null,
    fatG: null,
    carbsG: null,
    macroCoverage: 0,
    logCount: 0,
    macroLogCount: 0,
  );

  /// 完全没有营养数据（有条目但一条都没给宏量）
  bool get hasNoMacroData => logCount > 0 && macroCoverage == 0;

  /// 部分有（0 < coverage < 1）
  bool get isPartial => macroCoverage > 0 && macroCoverage < 1;

  /// 全部有
  bool get isComplete => macroCoverage >= 1;
}
