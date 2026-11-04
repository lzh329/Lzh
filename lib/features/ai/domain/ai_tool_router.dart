import 'dart:convert';

import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 合并工具名（模型看到的 8 个写入口）
class AiMergedTools {
  AiMergedTools._();

  static const workout = 'workout';
  static const body = 'body';
  static const diet = 'diet';
  static const settings = 'settings';
  static const template = 'template';
  static const exercise = 'exercise';
  static const goal = 'goal';
  static const erase = 'erase';

  static const all = <String>{
    workout,
    body,
    diet,
    settings,
    template,
    exercise,
    goal,
    erase,
  };

  /// 每个工具允许的 action（也是 schema 的 enum 来源）
  static const actions = <String, List<String>>{
    workout: ['log', 'update', 'delete', 'start'],
    body: ['weight', 'measurements', 'update_measurement'],
    diet: ['food', 'water'],
    settings: ['target_weight', 'diet_target', 'profile', 'reminder'],
    template: ['create', 'delete'],
    exercise: ['create', 'create_many'],
    goal: ['create', 'complete', 'delete'],
    erase: ['records', 'all'],
  };
}

/// 合并工具 → 旧工具名的**唯一翻译表**
///
/// 整个收敛只在这里做映射：handler / executor / 仓储一行不改，
/// 出问题把 [AiToolSpecs.useLegacyTools] 置 true 就回到旧工具面。
const Map<String, Map<String, String>> _routeTable = {
  AiMergedTools.workout: {
    'log': AiToolSpecs.logWorkout,
    'update': AiToolSpecs.updateWorkout,
    'delete': AiToolSpecs.deleteWorkout,
    'start': AiToolSpecs.startWorkout,
  },
  AiMergedTools.body: {
    'weight': AiToolSpecs.logWeight,
    'measurements': AiToolSpecs.logMeasurements,
    'update_measurement': AiToolSpecs.updateMeasurement,
  },
  AiMergedTools.diet: {
    'food': AiToolSpecs.logFood,
    'water': AiToolSpecs.logWater,
  },
  AiMergedTools.settings: {
    'target_weight': AiToolSpecs.setTargetWeight,
    'diet_target': AiToolSpecs.setDietTarget,
    'profile': AiToolSpecs.updateProfile,
    'reminder': AiToolSpecs.setReminder,
  },
  AiMergedTools.template: {
    'create': AiToolSpecs.createTemplate,
    'delete': AiToolSpecs.deleteTemplate,
  },
  AiMergedTools.exercise: {
    'create': AiToolSpecs.createExercise,
    'create_many': AiToolSpecs.createExercises,
  },
  AiMergedTools.goal: {
    'create': AiToolSpecs.manageGoal,
    'complete': AiToolSpecs.manageGoal,
    'delete': AiToolSpecs.manageGoal,
  },
  AiMergedTools.erase: {
    'records': AiToolSpecs.deleteRecords,
    'all': AiToolSpecs.wipeAllData,
  },
};

/// 把合并工具的调用规范化成旧工具调用（**唯一翻译点**）
///
/// - `{name:'workout', args:{action:'log', ...}}` → `{name:'log_workout', args:{...}}`
///   （剥掉 `action`，其余参数原样保留）
/// - `goal` 需要把 action 转成 `manage_goal` 自己的 `action` 字段
/// - `erase` 的 action → `kind` 语义即旧工具的 kind/type 参数，原样保留
/// - 本来就是旧工具名的调用 → 原样返回（兼容混用）
AiToolCall normalize(AiToolCall call) {
  final actions = _routeTable[call.name];
  if (actions == null) return call; // 旧工具名或只读工具：不翻译

  final args = Map<String, dynamic>.from(call.arguments);
  final rawAction = args.remove('action');
  final action = rawAction is String ? rawAction.trim() : '';
  final legacy = actions[action];
  if (legacy == null) {
    throw AiToolException('${call.name} 不支持 action「$action」，可选：'
        '${actions.keys.join(' / ')}');
  }

  // manage_goal 用同一个工具承载 create/complete/delete，靠自身 action 区分
  if (legacy == AiToolSpecs.manageGoal) {
    args['action'] = action;
  }
  return AiToolCall(
    id: call.id,
    name: legacy,
    argumentsJson: jsonEncode(args),
  );
}

/// 合并层的危险判定：**工具名 + action**
///
/// 旧实现只看工具名；合并后 `workout` 既有记记录（安全）也有删记录（危险），
/// 只能按 action 判。
bool isMergedDestructive(String name, String action) {
  switch (name) {
    case AiMergedTools.erase:
      return true; // 删记录 / 清空全部，都红卡
    case AiMergedTools.workout:
      return action == 'delete';
    case AiMergedTools.body:
      return action == 'update_measurement';
    case AiMergedTools.template:
      return action == 'delete';
    case AiMergedTools.goal:
      return action == 'delete';
    default:
      return false;
  }
}
