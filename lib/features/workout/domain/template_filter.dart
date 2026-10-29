import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';

/// 难度三档（固定枚举，永远全部显示；空档由 UI 置灰）
const List<String> kDifficultyOrder = <String>['入门', '中阶', '高阶'];

/// 「全部」占位值
const String kAllFilter = '全部';

/// 推荐模板过滤：场景（focus）× 难度（difficulty）**AND 组合**
///
/// 抽成纯函数的理由：这是页面上唯一需要"想清楚"的规则（两个维度、各自可
/// 为"全部"、还允许数据里出现未知 focus），放在 widget 里只能靠人肉点界面验；
/// 纯函数可以穷举覆盖。
List<WorkoutTemplateEntity> filterTemplates(
  List<WorkoutTemplateEntity> templates, {
  String focus = kAllFilter,
  String difficulty = kAllFilter,
}) {
  return templates.where((t) {
    final focusOk = focus == kAllFilter || t.focus == focus;
    final difficultyOk = difficulty == kAllFilter || t.difficulty == difficulty;
    return focusOk && difficultyOk;
  }).toList();
}

/// 固定三档在**当前场景筛选结果**下各有多少个模板（用于把空档置灰）
///
/// 注意只按 focus 统计、不按当前难度统计 —— 否则选中"入门"后另外两档
/// 会全部变成 0 而被置灰，用户就没法切回去了。
Map<String, int> difficultyCounts(
  List<WorkoutTemplateEntity> templates, {
  String focus = kAllFilter,
}) {
  return {
    for (final d in kDifficultyOrder)
      d: filterTemplates(templates, focus: focus, difficulty: d).length,
  };
}
