import 'package:drift/native.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/reminder_scheduler.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';
import 'package:fittrack/features/goal/data/goal_repository_impl.dart';
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
    reminderScheduler: fakeReminderScheduler(),
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


/// 什么都不做的排期入口（AI 工具测试用：不碰通知通道）
ReminderScheduler fakeReminderScheduler([AppDatabase? provided]) {
  final db = provided ?? fakeDatabase();
  return ReminderScheduler(
    sink: const _NoopSink(),
    gate: SickDayGate(
      DailyOverrideRepository(db),
      UserSettingsRepositoryImpl(db),
    ),
  );
}

class _NoopSink implements ReminderSink {
  const _NoopSink();

  @override
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) async {}

  @override
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) async {}

  @override
  Future<void> cancelById(int id) async {}

  @override
  Future<void> cancelAll() async {}
}
