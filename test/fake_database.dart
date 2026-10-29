import 'package:drift/native.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';
import 'package:fittrack/features/goal/data/goal_repository_impl.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepositoryImpl;
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';

/// 测试用假库：内存 + 不灌种子（wipe 之外的用例不碰这些表）
AppDatabase fakeDatabase() => AppDatabase.withExecutor(NativeDatabase.memory());

/// 真 · 内存库 + 全套真仓储（AI 工具测试用；不发网络、不碰平台通道）
AiToolRepos fakeToolRepos([AppDatabase? provided]) {
  final db = provided ?? fakeDatabase();
  return AiToolRepos(
    database: db,
    body: BodyMetricRepositoryImpl(db),
    water: WaterRepositoryImpl(db),
    workout: WorkoutRepositoryImpl(db),
    diet: DietRepositoryImpl(db),
    goal: GoalRepositoryImpl(db),
    settings: UserSettingsRepositoryImpl(db),
    exercise: ExerciseRepositoryImpl(db),
    template: WorkoutTemplateRepositoryImpl(db),
  );
}
