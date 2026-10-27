import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';

/// 训练启动类：start_workout —— 把训练模板翻译成训练页的初始槽位
///
/// 这个工具**不写数据库**：它只把模板「翻译」成 `List<ExerciseSlot>` 形状的
/// JSON，由界面拿去做跳转（见 AiChatState.pendingWorkoutStart）。
/// 因为会触发界面跳转（用户可感知的副作用），它仍然走确认卡，
/// 但删不了任何数据，所以不是危险操作。
class AiToolWorkoutLauncher extends AiToolHandler {
  const AiToolWorkoutLauncher(super.repos);

  /// rest_sec 缺省链的最后一档（前两档来自用户设置）
  static const fallbackRestSec = 90;

  @override
  Set<String> get toolNames => const {AiToolSpecs.startWorkout};

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    // 参数越界、模板不存在都在预览阶段拦掉：不让用户点了确认才发现开不了练
    final name = AiToolArgs.startWorkoutTemplateName(call.arguments);
    AiToolArgs.optionalRestSec(call.arguments);
    final template = await _matchTemplate(name);
    return AiToolPreview(
      call: call,
      label: '开始训练',
      detail: '${template.name} · ${template.items.length} 个动作 · '
          '约 ${template.minutes} 分钟',
      needsConfirm: true,
    );
  }

  @override
  Future<String> execute(AiToolCall call) async {
    final args = call.arguments;
    final template = await _matchTemplate(
      AiToolArgs.startWorkoutTemplateName(args),
    );
    final restSec = await _resolveRestSec(AiToolArgs.optionalRestSec(args));
    return jsonEncode({
      'ok': true,
      'action': AiToolSpecs.startWorkout,
      'template': template.name,
      'slots': [
        for (final item in template.items)
          {
            'exerciseId': item.exerciseId,
            'exerciseName': item.exerciseName,
            'category': item.category,
            'targetSets': item.targetSets,
            'targetReps': item.targetReps,
            'targetDurationSec': item.targetDurationSec,
            'restSec': restSec,
          },
      ],
    });
  }

  /// 按模板名匹配（trim + 忽略大小写）；匹配不到 / 模板没动作就抛异常
  Future<WorkoutTemplateEntity> _matchTemplate(String name) async {
    final key = name.trim().toLowerCase();
    final all = await repos.template.getAll();
    for (final template in all) {
      if (template.name.trim().toLowerCase() != key) continue;
      if (template.items.isEmpty) {
        throw AiToolException('模板"${template.name}"还没有动作，先给它加几个动作再开练');
      }
      return template;
    }
    throw AiToolException('没找到模板"$name"，要不要我帮你建一个？');
  }

  /// 休息时长缺省链：入参 → 设置里的 restShortSec → 设置里的 defaultRestSec → 90
  ///
  /// 读设置失败不该让「开练」失败：读不出来就按 90 兜底（用户可以在训练页改）。
  Future<int> _resolveRestSec(int? fromArgs) async {
    if (fromArgs != null) return fromArgs;
    final UserSettingsEntity? settings;
    try {
      settings = await repos.settings.get();
    } catch (e) {
      debugPrint('读取休息时长设置失败，按 $fallbackRestSec 秒兜底: $e');
      return fallbackRestSec;
    }
    final short = settings?.restShortSec;
    if (short != null && short > 0) return short;
    final normal = settings?.defaultRestSec;
    if (normal != null && normal > 0) return normal;
    return fallbackRestSec;
  }
}
