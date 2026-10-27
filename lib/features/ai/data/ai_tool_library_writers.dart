import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_exercise_writer.dart';
import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// 动作库 / 模板类写操作：create_exercise / create_exercises / create_template
///
/// 三个工具都要走确认卡；动作名的解析与查重统一走 [AiExerciseWriter]。
///
/// create_template 支持一次补齐缺失动作（`create_missing_exercises`）：
/// 预览阶段只**解析**出待新建清单（不写库、不缓存到下一个请求），确认后按
/// "先建动作、再建模板"的顺序落库，全程只发生在同一次确认里。
class AiToolLibraryWriters extends AiToolHandler {
  const AiToolLibraryWriters(super.repos);

  /// 动作库写入器（无状态，随用随建，避免跨请求共享可变数据）
  AiExerciseWriter get _writer => AiExerciseWriter(repos);

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.createExercise,
        AiToolSpecs.createExercises,
        AiToolSpecs.createTemplate,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.createExercise:
        final input = AiToolArgs.exercise(call.arguments);
        // 预览阶段就查重：同名动作提前报错，别让用户点了确认才发现建不了
        await _writer.ensureAbsent(input.name);
        return AiToolPreview(
          call: call,
          label: '新增动作',
          detail: '新增动作：${input.name}（${input.metaLabel}）',
          needsConfirm: true,
        );
      case AiToolSpecs.createExercises:
        final inputs = AiToolArgs.exercises(call.arguments);
        return AiToolPreview(
          call: call,
          label: '批量新增动作',
          detail:
              '新增 ${inputs.length} 个动作：${inputs.map((e) => e.name).join('、')}',
          needsConfirm: true,
        );
      case AiToolSpecs.createTemplate:
        final command = AiToolArgs.template(call.arguments);
        // 预览阶段就解析动作名：库里缺动作且没开开关时提前报错，不打扰用户确认
        final missing = _missingOf(command, await _writer.library());
        _ensureMissingAllowed(command, missing);
        return AiToolPreview(
          call: call,
          label: '新建训练模板',
          detail: command.detailWith(missingCount: missing.length),
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
        return _writer.createOne(AiToolArgs.exercise(call.arguments));
      case AiToolSpecs.createExercises:
        return _writer.createMany(AiToolArgs.exercises(call.arguments));
      case AiToolSpecs.createTemplate:
        return _createTemplate(AiToolArgs.template(call.arguments));
      default:
        unsupported(call);
    }
  }

  // ───────────── create_template ─────────────

  /// 待新建的动作清单：库里没有的，按名字去重（同名只建一个，忽略大小写）
  static List<AiTemplateItemInput> _missingOf(
      AiTemplateCommand command, Map<String, ExerciseEntity> library) {
    final seen = <String>{};
    final missing = <AiTemplateItemInput>[];
    for (final item in command.items) {
      final key = item.nameKey;
      if (library.containsKey(key) || !seen.add(key)) continue;
      missing.add(item);
    }
    return missing;
  }

  /// 缺动作且未开启 `create_missing_exercises` → 保持原行为直接报错
  static void _ensureMissingAllowed(
      AiTemplateCommand command, List<AiTemplateItemInput> missing) {
    if (missing.isEmpty || command.createMissingExercises) return;
    throw AiToolException(
        '动作库里没有"${missing.first.exerciseName}"，先添加这个动作再建模板');
  }

  /// 新建模板：先补齐缺失动作，再把动作名全部映射成库内 id 落库
  Future<String> _createTemplate(AiTemplateCommand command) async {
    final writer = _writer;
    final library = await writer.library();
    // 1) 待新建清单（这里会做"缺动作且未开开关"的拦截）
    final missing = _missingOf(command, library);
    _ensureMissingAllowed(command, missing);

    // 2) 先创建缺失动作：同名（忽略大小写）已存在则复用，不重复建
    final createdNames = <String>[];
    for (final item in missing) {
      final key = item.nameKey;
      if (library.containsKey(key)) continue; // 二次校验：已经有就复用
      final entity = await writer.insert(item.toNewExercise());
      library[key] = entity;
      createdNames.add(entity.name);
    }

    // 3) 再建模板：items 全部映射到 id（此时每个名字都一定能在库里找到）
    final items = <TemplateItemInput>[];
    for (final item in command.items) {
      final hit = library[item.nameKey];
      if (hit == null) {
        throw AiToolException(
            '动作库里没有"${item.exerciseName}"，先添加这个动作再建模板');
      }
      items.add(TemplateItemInput(
        exerciseId: hit.id,
        targetSets: item.sets,
        targetReps: item.reps,
        targetDurationSec: item.durationSec,
      ));
    }

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
      'template_id': id,
      'created_exercises': createdNames,
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
}
