import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

/// 把模板展开成"训练里的一组组记录"（**纯函数**，可单测）
///
/// 为什么必须走模板展开：用户说"用 XX 模板补记"，组次/时长只有模板里是准的。
/// 让模型把模板口述成 exercises[] 会在翻译过程中丢掉 targetReps /
/// targetDurationSec —— 真机上每组就变成"未记录"。
///
/// 规则：
/// - 每个 item 重复 `targetSets` 次，setNumber 从 1 开始
/// - reps / durationSec **只取模板值**，不用动作库默认值覆盖
///   （覆盖等于篡改用户设过的模板）
/// - 空模板抛错：没有动作可展开，不能记成"0 组"
List<NewSetData> expandTemplateSets(WorkoutTemplateEntity template) {
  if (template.items.isEmpty) {
    throw TemplateEmptyException(template.name);
  }
  final sets = <NewSetData>[];
  for (final item in template.items) {
    final count = item.targetSets < 1 ? 1 : item.targetSets;
    for (var i = 1; i <= count; i++) {
      sets.add(NewSetData(
        exerciseId: item.exerciseId,
        setNumber: i,
        reps: item.targetReps,
        durationSec: item.targetDurationSec,
        weightKg: null,
        isWarmup: false,
      ));
    }
  }
  return sets;
}

/// 模板里没有动作（domain 层异常，由调用方转成用户可读文案）
class TemplateEmptyException implements Exception {
  final String templateName;
  const TemplateEmptyException(this.templateName);

  @override
  String toString() => '模板「$templateName」里还没有动作';
}
