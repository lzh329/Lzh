import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';

/// 难度三档（固定枚举，永远全部显示；空档由 UI 置灰）
const List<String> kDifficultyOrder = <String>['入门', '中阶', '高阶'];

/// 「全部」占位值
const String kAllFilter = '全部';

/// 类型两档（力量 / 有氧）—— 界面上是分段控件：全部 / 力量 / 有氧
const List<String> kTypeOrder = <String>['力量', '有氧'];

/// 中文类型标签 → 实体里的 type 值
const Map<String, String> kTypeValues = <String, String>{
  '力量': 'strength',
  '有氧': 'cardio',
};

/// 推荐模板过滤：类型（type）× 难度（difficulty）**AND 组合**
///
/// `type` 收的是**中文标签**（全部/力量/有氧），与 UI 分段控件一致；
/// 内部映射到实体的 `strength`/`cardio`。原来的「场景（focus）」维度已
/// 整组删除（产品决策），focus 字段保留在库里但不再参与筛选。
List<WorkoutTemplateEntity> filterTemplates(
  List<WorkoutTemplateEntity> templates, {
  String type = kAllFilter,
  String difficulty = kAllFilter,
}) {
  final wanted = kTypeValues[type];
  return templates.where((t) {
    final typeOk = type == kAllFilter || t.type == wanted;
    final difficultyOk = difficulty == kAllFilter || t.difficulty == difficulty;
    return typeOk && difficultyOk;
  }).toList();
}

/// 固定三档在**当前类型筛选结果**下各有多少个模板（用于把空档置灰）
///
/// 注意只按 type 统计、不按当前难度统计 —— 否则选中"入门"后另外两档
/// 会全部变成 0 而被置灰，用户就没法切回去了。
Map<String, int> difficultyCounts(
  List<WorkoutTemplateEntity> templates, {
  String type = kAllFilter,
}) {
  return {
    for (final d in kDifficultyOrder)
      d: filterTemplates(templates, type: type, difficulty: d).length,
  };
}
