import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';

/// 动作库写入：名称解析 + 查重 + 落库
///
/// create_exercise / create_exercises / create_template 三条路径共用同一口径：
/// 动作名一律按"库内 trim 后精确匹配（忽略大小写）"解析，绝不按模型想象的 id 写库。
class AiExerciseWriter {
  const AiExerciseWriter(this.repos);

  final AiToolRepos repos;

  /// 动作名归一化：trim + 小写（中文不受影响，英文 "Plank"/"plank" 视为同名）
  static String nameKey(String name) => name.trim().toLowerCase();

  /// 动作库索引：同名多个只取第一个（保持库内顺序稳定）
  Future<Map<String, ExerciseEntity>> library() async {
    final exercises = await repos.exercise.getAll();
    final byName = <String, ExerciseEntity>{};
    for (final e in exercises) {
      byName.putIfAbsent(nameKey(e.name), () => e);
    }
    return byName;
  }

  /// 同名动作已存在则抛异常（预览与执行共用同一口径）
  Future<void> ensureAbsent(String name) async {
    final library = await this.library();
    if (library.containsKey(nameKey(name))) {
      throw AiToolException('动作库里已有"$name"');
    }
  }

  /// 落库一个动作（调用方已做完同名校验）
  Future<ExerciseEntity> insert(AiExerciseInput input) async {
    final created =
        await repos.exercise.create(input.name, input.category, input.muscleGroup);
    if (input.hasDefaults) {
      await repos.exercise.saveDefaults(
        created.id,
        defaultReps: input.defaultReps,
        defaultDurationSec: input.defaultDurationSec,
      );
    }
    return created;
  }

  /// 单个新增：同名已存在则拒绝（避免动作库长出重复项）
  Future<String> createOne(AiExerciseInput input) async {
    // 兜底：预览到确认之间库可能已被别处改动，写库前再查一次
    await ensureAbsent(input.name);
    final created = await insert(input);
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

  /// 批量新增：已存在的同名动作跳过并计入 skipped，其余逐个落库
  Future<String> createMany(List<AiExerciseInput> inputs) async {
    final library = await this.library();
    final created = <Map<String, Object?>>[];
    final skipped = <String>[];
    for (final input in inputs) {
      final key = nameKey(input.name);
      // 二次校验：库里已有（或本批前面刚建过）就复用，不重复写库
      if (library.containsKey(key)) {
        skipped.add(input.name);
        continue;
      }
      final entity = await insert(input);
      library[key] = entity; // 同批后面的重名也能被拦下
      created.add({'id': entity.id, 'name': entity.name});
    }
    return jsonEncode({
      'ok': true,
      'created_count': created.length,
      'created': created,
      'skipped': skipped,
    });
  }
}
