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

  const FoodLogEntity({
    required this.id,
    required this.date,
    required this.foodId,
    required this.grams,
    required this.mealType,
    this.foodName,
    this.caloriesPer100g,
  });

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
