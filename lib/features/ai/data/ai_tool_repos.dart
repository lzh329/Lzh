import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// 工具执行所需的仓储集合
///
/// 集中注入，避免每个处理器都摊开一长串构造参数。
class AiToolRepos {
  /// 数据库本体（wipe 这类全表操作要直接跑 DELETE，不经过单个仓储）
  final AppDatabase database;

  final BodyMetricRepository body;
  final WaterRepository water;
  final WorkoutRepository workout;
  final DietRepository diet;
  final GoalRepository goal;
  final UserSettingsRepository settings;

  /// 动作库（query_exercises / create_exercise）
  final ExerciseRepository exercise;

  /// 训练模板（create_template）
  final WorkoutTemplateRepository template;

  const AiToolRepos({
    required this.database,
    required this.body,
    required this.water,
    required this.workout,
    required this.diet,
    required this.goal,
    required this.settings,
    required this.exercise,
    required this.template,
  });

  /// 从 providers 构建（工具执行时即时读取，不做 watch）
  factory AiToolRepos.fromRef(Ref ref) => AiToolRepos(
        database: ref.read(databaseProvider),
        body: ref.read(bodyMetricRepoProvider),
        water: ref.read(waterRepoProvider),
        workout: ref.read(workoutRepoProvider),
        diet: ref.read(dietRepoProvider),
        goal: ref.read(goalRepoProvider),
        settings: ref.read(userSettingsRepoProvider),
        exercise: ref.read(exerciseRepoProvider),
        template: ref.read(workoutTemplateRepoProvider),
      );
}
