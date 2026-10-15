class GoalEntity {
  final int id;
  final String type; // weight, frequency, custom
  final String? category; // 自定义目标分类标签
  final double targetValue;
  final double currentValue;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isCompleted;
  final DateTime createdAt;

  const GoalEntity({
    required this.id,
    required this.type,
    this.category,
    required this.targetValue,
    required this.currentValue,
    required this.startDate,
    this.endDate,
    this.isCompleted = false,
    required this.createdAt,
  });

  double get progressPercent {
    if (targetValue <= 0) return 0;
    return (currentValue / targetValue * 100).clamp(0, 100);
  }

  static const typeLabels = {
    'weight': '体重目标',
    'frequency': '训练频率',
    'custom': '自定义',
  };

  static const typeIcons = {
    'weight': 'monitor_weight',
    'frequency': 'calendar_month',
    'custom': 'flag',
  };
}
