import 'dart:convert';

import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart'
    show ExerciseSlot;

/// 「开始训练」意图：start_workout 工具结果解析出来的训练计划
///
/// 工具只负责把模板翻译成槽位，**不写数据库**；真正的「进训练页」由界面做，
/// 所以这里只做纯解析，解析不出来就返回 null（界面据此决定跳不跳）。
class AiWorkoutIntent {
  /// 模板名（用于跳转后的提示语）
  final String templateName;

  /// 已初始化好组数 / 次数的动作槽位
  final List<ExerciseSlot> slots;

  const AiWorkoutIntent({required this.templateName, required this.slots});

  /// 解析不出来时用的兜底模板名（跳转提示语不能空着）
  static const fallbackTemplateName = '训练模板';

  /// 槽位缺 [ExerciseSlot.restSec] 时的兜底休息时长（秒）
  static const fallbackRestSec = 90;

  /// 解析 start_workout 的返回 JSON
  ///
  /// 任何一处不对（非法 JSON / ok 不为 true / slots 为空 / 字段缺失或类型错）
  /// 都返回 null：宁可让用户重试一次，也不要带着半残的槽位跳进训练页。
  static AiWorkoutIntent? parse(String toolResultJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(toolResultJson);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['ok'] != true) return null;

    final rawSlots = decoded['slots'];
    if (rawSlots is! List || rawSlots.isEmpty) return null;

    final slots = <ExerciseSlot>[];
    for (final raw in rawSlots) {
      final slot = slotOf(raw);
      if (slot == null) return null;
      slots.add(slot);
    }

    final rawName = decoded['template'];
    final name = rawName is String ? rawName.trim() : '';
    return AiWorkoutIntent(
      templateName: name.isEmpty ? fallbackTemplateName : name,
      slots: slots,
    );
  }

  /// 单个槽位：必填字段（id / 名称 / 分类 / 组数）缺一个就返回 null
  static ExerciseSlot? slotOf(Object? raw) {
    if (raw is! Map) return null;

    final exerciseId = _intOf(raw['exerciseId']);
    final targetSets = _intOf(raw['targetSets']);
    final exerciseName = raw['exerciseName'];
    final category = raw['category'];

    if (exerciseId == null || exerciseId <= 0) return null;
    if (targetSets == null || targetSets <= 0) return null;
    if (exerciseName is! String || exerciseName.trim().isEmpty) return null;
    if (category is! String || category.trim().isEmpty) return null;
    // 可选项：可以有 / 可以是 null，但给了就必须是整数
    if (_isMalformed(raw, 'targetReps') ||
        _isMalformed(raw, 'targetDurationSec') ||
        _isMalformed(raw, 'restSec')) {
      return null;
    }

    final reps = _intOf(raw['targetReps']);
    final duration = _intOf(raw['targetDurationSec']);
    final rest = _intOf(raw['restSec']);

    return ExerciseSlot(
      exerciseId: exerciseId,
      exerciseName: exerciseName.trim(),
      category: category.trim(),
      targetSets: targetSets,
      targetReps: reps != null && reps > 0 ? reps : null,
      targetDurationSec: duration != null && duration > 0 ? duration : null,
      restSec: rest != null && rest > 0 ? rest : fallbackRestSec,
    );
  }

  /// 字段存在但不是整数（类型错）——不能当成"没给"静默放过
  static bool _isMalformed(Map<dynamic, dynamic> raw, String key) {
    final value = raw[key];
    return value != null && _intOf(value) == null;
  }

  /// 整数解析：接受 int / double / 数字字符串，其他一律 null
  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is double) {
      return value == value.roundToDouble() ? value.toInt() : null;
    }
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// 只要槽位列表的便捷入口（解析失败返回 null）
List<ExerciseSlot>? parseWorkoutSlots(String toolResultJson) =>
    AiWorkoutIntent.parse(toolResultJson)?.slots;
