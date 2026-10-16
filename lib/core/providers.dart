import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';
import 'package:fittrack/features/plan/data/plan_repository_impl.dart';
import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';
import 'package:fittrack/features/body_log/data/photo_repository_impl.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/goal/data/goal_repository_impl.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart' show WaterRepository, WaterRepositoryImpl;
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

// ── 数据库 ──
final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

// ── 仓储 ──
final exerciseRepoProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepositoryImpl(ref.watch(databaseProvider));
});

final workoutRepoProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepositoryImpl(ref.watch(databaseProvider));
});

final bodyMetricRepoProvider = Provider<BodyMetricRepository>((ref) {
  return BodyMetricRepositoryImpl(ref.watch(databaseProvider));
});

final planRepoProvider = Provider<PlanRepository>((ref) {
  return PlanRepositoryImpl(ref.watch(databaseProvider));
});

final photoRepoProvider = Provider<PhotoRepository>((ref) {
  return PhotoRepositoryImpl(ref.watch(databaseProvider));
});

final goalRepoProvider = Provider<GoalRepository>((ref) {
  return GoalRepositoryImpl(ref.watch(databaseProvider));
});

final userSettingsRepoProvider = Provider<UserSettingsRepository>((ref) {
  return UserSettingsRepositoryImpl(ref.watch(databaseProvider));
});

// 身体信息——从 DB 异步加载
final userSettingsProvider = FutureProvider<UserSettingsEntity?>((ref) async {
  return ref.watch(userSettingsRepoProvider).get();
});

// ── 饮食 ──
final dietRepoProvider = Provider<DietRepository>((ref) {
  return DietRepositoryImpl(ref.watch(databaseProvider));
});

// ── 饮水 ──
final waterRepoProvider = Provider<WaterRepository>((ref) {
  return WaterRepositoryImpl(ref.watch(databaseProvider));
});

// ── 主题模式 ──
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

void initThemeMode(WidgetRef ref, {required String? themeMode}) {
  final mode = themeMode == 'dark' ? ThemeMode.dark : themeMode == 'light' ? ThemeMode.light : ThemeMode.dark;
  ref.read(themeModeProvider.notifier).state = mode;
}

// ── 首页数据 ──
// 数据变更方调用 ref.invalidate(dashboardDataProvider) 让其自动重算，无需手动刷新计数器

class DashboardData {
  final Set<DateTime> calendarWorkoutDates;
  final List<WorkoutEntity> allWorkouts;
  final List<WorkoutEntity> recentWorkouts;
  final BodyMetricEntity? latestMetric;
  final BodyMetricEntity? firstMetric;
  final BodyMetricEntity? weekStartMetric;
  final BodyMetricEntity? todayMetric;
  final List<BodyMetricEntity> allMetrics;
  final double? todayCalories;
  final Set<DateTime> weighInDates;
  final int todayCups;
  final List<GoalEntity> goals;
  final Map<int, String> exerciseNames;
  final int weekWorkoutDays;

  const DashboardData({
    this.calendarWorkoutDates = const {},
    this.allWorkouts = const [],
    this.recentWorkouts = const [],
    this.latestMetric,
    this.firstMetric,
    this.weekStartMetric,
    this.todayMetric,
    this.allMetrics = const [],
    this.todayCalories,
    this.weighInDates = const {},
    this.todayCups = 0,
    this.goals = const [],
    this.exerciseNames = const {},
    this.weekWorkoutDays = 0,
  });
}

final dashboardDataProvider = FutureProvider<DashboardData>((ref) async {
  final workoutRepo = ref.watch(workoutRepoProvider);
  final bodyRepo = ref.watch(bodyMetricRepoProvider);
  final goalRepo = ref.watch(goalRepoProvider);
  final exerciseRepo = ref.watch(exerciseRepoProvider);
  final dietRepo = ref.watch(dietRepoProvider);
  final waterRepo = ref.watch(waterRepoProvider);

  final now = DateTime.now();
  final calStart = DateTime(now.year, now.month - 3, 1);
  final calEnd = DateTime(now.year, now.month + 4, 0);
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  final todayStart = DateTime(now.year, now.month, now.day);

  final calWorkouts = await workoutRepo.getAll(from: calStart, to: calEnd);
  final recent = await workoutRepo.getAll();
  final latestMetric = await bodyRepo.getLatest();
  final goals = await goalRepo.getAll();
  final exercises = await exerciseRepo.getAll();
  final exerciseNames = {for (final e in exercises) e.id: e.name};
  final allMetrics = await bodyRepo.getAll();
  final firstMetric = allMetrics.isNotEmpty ? allMetrics.first : null;
  final weekMetrics = await bodyRepo.getAll(from: monday, to: now);
  final weekStartMetric = weekMetrics.isNotEmpty ? weekMetrics.first : null;
  final todayMetrics = await bodyRepo.getAll(from: todayStart, to: now);
  final todayMetric = todayMetrics.isNotEmpty ? todayMetrics.first : null;
  final todayCalories = await dietRepo.getDailyCalories(now);
  final weighInDates = allMetrics.map((m) => DateTime(m.date.year, m.date.month, m.date.day)).toSet();
  final todayCups = await waterRepo.getTodayCups();
  final weekWorkoutDays = recent
      .where((w) => !w.date.isBefore(monday))
      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
      .toSet()
      .length;

  return DashboardData(
    calendarWorkoutDates: calWorkouts.map((w) => DateTime(w.date.year, w.date.month, w.date.day)).toSet(),
    allWorkouts: calWorkouts,
    recentWorkouts: recent.take(3).toList(),
    latestMetric: latestMetric,
    firstMetric: firstMetric,
    weekStartMetric: weekStartMetric,
    todayMetric: todayMetric,
    allMetrics: allMetrics,
    todayCalories: todayCalories > 0 ? todayCalories : null,
    weighInDates: weighInDates,
    todayCups: todayCups,
    goals: goals.where((g) => !g.isCompleted).toList(),
    exerciseNames: exerciseNames,
    weekWorkoutDays: weekWorkoutDays,
  );
});

// ── 提醒设置 ──
final reminderEnabledProvider = StateProvider<bool>((ref) => false);
final reminderHourProvider = StateProvider<int>((ref) => 8);
final reminderMinuteProvider = StateProvider<int>((ref) => 0);

/// 从 UserSettings 初始化提醒状态
void initReminderState(WidgetRef ref, {bool enabled = false, int hour = 8, int minute = 0}) {
  ref.read(reminderEnabledProvider.notifier).state = enabled;
  ref.read(reminderHourProvider.notifier).state = hour;
  ref.read(reminderMinuteProvider.notifier).state = minute;
}
