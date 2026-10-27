import 'package:fittrack/features/ai/domain/ai_tool_exception.dart';

/// 围度输入：三项都可空，但至少要有一项（由 [AiToolArgs.measurements] 保证）
class AiMeasurements {
  final double? waistCm;
  final double? hipCm;
  final double? chestCm;

  const AiMeasurements({this.waistCm, this.hipCm, this.chestCm});

  bool get isEmpty => waistCm == null && hipCm == null && chestCm == null;

  /// 只列出有值的项，如「腰围 80cm · 臀围 95cm」
  String get label {
    final parts = <String>[];
    if (waistCm != null) parts.add('腰围 ${_num(waistCm!)}cm');
    if (hipCm != null) parts.add('臀围 ${_num(hipCm!)}cm');
    if (chestCm != null) parts.add('胸围 ${_num(chestCm!)}cm');
    return parts.join(' · ');
  }

  static String _num(double v) {
    final rounded = v.roundToDouble();
    return v == rounded ? rounded.round().toString() : v.toStringAsFixed(1);
  }
}

/// 身体信息输入：三项都可空，但至少要有一项
class AiProfileInput {
  final double? heightCm;
  final String? gender; // male / female
  final int? birthYear;

  const AiProfileInput({this.heightCm, this.gender, this.birthYear});

  bool get isEmpty => heightCm == null && gender == null && birthYear == null;

  static const genderLabels = {'male': '男', 'female': '女'};

  /// 如「身高 175cm · 男 · 1995 年生」，只列有值的项
  String get label {
    final parts = <String>[];
    if (heightCm != null) {
      final rounded = heightCm!.roundToDouble();
      parts.add('身高 ${heightCm == rounded ? rounded.round() : heightCm!.toStringAsFixed(1)}cm');
    }
    if (gender != null) parts.add(genderLabels[gender!] ?? gender!);
    if (birthYear != null) parts.add('$birthYear 年生');
    return parts.join(' · ');
  }
}

/// 饮食目标输入：四项都可空，但至少要有一项
class AiDietTargetInput {
  final int? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  const AiDietTargetInput({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  bool get isEmpty =>
      calories == null && proteinG == null && carbsG == null && fatG == null;

  /// 如「每日 1800 千卡 · 蛋白 120g · 碳水 150g」，只列有值的项
  String get label {
    final parts = <String>[];
    if (calories != null) parts.add('每日 $calories 千卡');
    if (proteinG != null) parts.add('蛋白 ${_g(proteinG!)}g');
    if (carbsG != null) parts.add('碳水 ${_g(carbsG!)}g');
    if (fatG != null) parts.add('脂肪 ${_g(fatG!)}g');
    return parts.join(' · ');
  }

  static String _g(double v) {
    final rounded = v.roundToDouble();
    return v == rounded ? rounded.round().toString() : v.toStringAsFixed(1);
  }
}

/// manage_goal 的参数集合（create / complete / delete 共用）
class AiGoalCommand {
  final String action; // create / complete / delete
  final int? goalId;
  final String? type; // weight / frequency / custom
  final double? targetValue;
  final String? category;
  final DateTime? endDate;

  const AiGoalCommand({
    required this.action,
    this.goalId,
    this.type,
    this.targetValue,
    this.category,
    this.endDate,
  });

  bool get isCreate => action == 'create';

  /// 删除动作属于危险操作：确认卡走警示样式
  bool get isDestructive => AiGoalActions.destructive.contains(action);

  /// 目标展示单位：体重目标按「斤」，频率目标按「次」，其他不带单位
  String get unitLabel => switch (type) {
        'weight' => ' 斤',
        'frequency' => ' 次',
        _ => '',
      };

  /// 新建目标的确认文案，如「新建体重目标：140 斤」
  String get createDetail {
    final typeLabel = _typeLabels[type] ?? '自定义目标';
    final value = targetValue ?? 0;
    final rounded = value.roundToDouble();
    final text = value == rounded
        ? rounded.round().toString()
        : value.toStringAsFixed(1);
    return '新建$typeLabel：$text$unitLabel';
  }

  static const _typeLabels = {
    'weight': '体重目标',
    'frequency': '训练频率目标',
    'custom': '自定义目标',
  };
}

/// manage_goal 的 action 枚举
class AiGoalActions {
  AiGoalActions._();

  static const create = 'create';
  static const complete = 'complete';
  static const delete = 'delete';
  static const all = {create, complete, delete};

  /// 危险动作：删除目标（create / complete 不算）
  static const destructive = {delete};
}

/// delete_records 的记录类型
class AiRecordTypes {
  AiRecordTypes._();

  static const weight = 'weight';
  static const food = 'food';
  static const workout = 'workout';
  static const water = 'water';
  static const all = {weight, food, workout, water};

  static const labels = {
    weight: '体重',
    food: '饮食',
    workout: '训练',
    water: '饮水',
  };

  static String labelOf(String type) => labels[type] ?? '记录';

  /// 空记录时的提示，如「这天没有可删除的饮食记录」
  static AiToolException emptyOf(String type) =>
      AiToolException('这天没有可删除的${labelOf(type)}记录');
}
