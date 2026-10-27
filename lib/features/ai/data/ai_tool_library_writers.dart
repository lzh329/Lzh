import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// 动作库 / 模板类写操作：create_exercise / create_template
///
/// 两个工具都要走确认卡；动作名一律按"库内 trim 后精确匹配（忽略大小写）"解析，
/// 绝不按模型想象的动作 id 写库。
class AiToolLibraryWriters extends AiToolHandler {
  const AiToolLibraryWriters(super.repos);

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.createExercise,
        AiToolSpecs.createTemplate,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.createExercise:
        final input = AiToolArgs.exercise(call.arguments);
        // 预览阶段就查重：同名动作提前报错，别让用户点了确认才发现建不了
        await _ensureExerciseAbsent(input.name);
        return AiToolPreview(
          call: call,
          label: '新增动作',
          detail: '新增动作：${input.name}（${input.metaLabel}）',
          needsConfirm: true,
        );
      case AiToolSpecs.createTemplate:
        final command = AiToolArgs.template(call.arguments);
        // 预览阶段就解析动作名：库里缺动作时提前报错，不打扰用户确认
        await _resolveItems(command.items);
        return AiToolPreview(
          call: call,
          label: '新建训练模板',
          detail: command.detail,
          needsConfirm: true,
        );
      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.createExercise:
        return _createExercise(AiToolArgs.exercise(call.arguments));
      case AiToolSpecs.createTemplate:
        return _createTemplate(AiToolArgs.template(call.arguments));
      default:
        unsupported(call);
    }
  }

  // ───────────── create_exercise ─────────────

  /// 动作名归一化：trim + 小写（中文不受影响，英文 "Plank"/"plank" 视为同名）
  static String _nameKey(String name) => name.trim().toLowerCase();

  /// 同名动作已存在则抛异常（预览与执行共用同一口径）
  Future<void> _ensureExerciseAbsent(String name) async {
    final key = _nameKey(name);
    final exercises = await repos.exercise.getAll();
    if (exercises.any((e) => _nameKey(e.name) == key)) {
      throw AiToolException('动作库里已有"$name"');
    }
  }

  /// 新建动作：同名（trim 后忽略大小写）已存在则拒绝，避免动作库长出重复项
  Future<String> _createExercise(AiExerciseInput input) async {
    // 兜底：预览到确认之间库可能已被别处改动，写库前再查一次
    await _ensureExerciseAbsent(input.name);

    final created = await repos.exercise
        .create(input.name, input.category, input.muscleGroup);

    if (input.hasDefaults) {
      await repos.exercise.saveDefaults(
        created.id,
        defaultReps: input.defaultReps,
        defaultDurationSec: input.defaultDurationSec,
      );
    }

    return jsonEncode({
      'ok': true,
      'created': {
        'id': created.id,
        'name': created.name,
        'category': created.category,
        'muscle_group': created.muscleGroup,
        'default_reps': input.defaultReps,
        'default_duration_sec': input.defaultDurationSec,
      },
    });
  }

  // ───────────── create_template ─────────────

  /// 新建模板：动作名先解析成库内 id，再交给仓储落库
  Future<String> _createTemplate(AiTemplateCommand command) async {
    final items = await _resolveItems(command.items);
    final id = await repos.template.create(
      name: command.name,
      difficulty: command.difficulty,
      focus: command.focus,
      minutes: command.minutes,
      description: command.description,
      items: items,
    );
    return jsonEncode({
      'ok': true,
      'created': {
        'id': id,
        'name': command.name,
        'difficulty': command.difficulty,
        'focus': command.focus,
        'minutes': command.minutes,
        'items': [
          for (var i = 0; i < command.items.length; i++)
            {
              'exercise_id': items[i].exerciseId,
              'exercise_name': command.items[i].exerciseName,
              'sets': items[i].targetSets,
              'reps': items[i].targetReps,
              'duration_sec': items[i].targetDurationSec,
            },
        ],
      },
    });
  }

  /// 动作名 → TemplateItemInput；库里找不到就抛异常让模型先加动作
  Future<List<TemplateItemInput>> _resolveItems(
      List<AiTemplateItemInput> items) async {
    final exercises = await repos.exercise.getAll();
    final byName = <String, ExerciseEntity>{};
    for (final e in exercises) {
      // 多个同名动作取第一个（保持库内顺序稳定）
      byName.putIfAbsent(_nameKey(e.name), () => e);
    }

    final resolved = <TemplateItemInput>[];
    for (final item in items) {
      final hit = byName[_nameKey(item.exerciseName)];
      if (hit == null) {
        throw AiToolException(
            '动作库里没有"${item.exerciseName}"，先添加这个动作再建模板');
      }
      resolved.add(TemplateItemInput(
        exerciseId: hit.id,
        targetSets: item.sets,
        targetReps: item.reps,
        targetDurationSec: item.durationSec,
      ));
    }
    return resolved;
  }
}
