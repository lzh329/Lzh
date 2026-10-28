import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';
import 'package:fittrack/features/plan/data/plan_repository_impl.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';
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
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository, WaterRepositoryImpl;
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';

// ── 数据库 ──
/// 全 App 唯一的数据库实例。
///
/// 封存态（库文件已被恢复流程替换、当前连接不可再信任）下直接抛错：
/// 让调用方拿到一个明确的"请重启"，而不是继续读一个已被 rename 的旧库 ——
/// 后者会表现为"数据莫名其妙回到恢复前"，比报错难查得多。
final databaseProvider = Provider<AppDatabase>((ref) {
  if (DatabaseSeal.sealed) {
    throw StateError(DatabaseSeal.message);
  }
  return AppDatabase();
});

/// AI 教练聊天记录仓库
final aiChatRepoProvider = Provider<AiChatRepository>((ref) {
  return AiChatRepository(ref.watch(databaseProvider));
});

// ── 仓储 ──
final exerciseRepoProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepositoryImpl(ref.watch(databaseProvider));
});

final workoutRepoProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepositoryImpl(ref.watch(databaseProvider));
});

/// 训练模板仓库（v12 数据库化：推荐模板 + 我的模板）
final workoutTemplateRepoProvider = Provider<WorkoutTemplateRepository>((ref) {
  return WorkoutTemplateRepositoryImpl(ref.watch(databaseProvider));
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

// ── 按日覆盖（v21）──
// 横跨饮食/训练/提醒三个域，不属于任何单一 feature，故仓库放在 core/database。
// 本期只有"生病闸门"会用，UI 与策略都不在这里。
final dailyOverrideRepoProvider = Provider<DailyOverrideRepository>((ref) {
  return DailyOverrideRepository(ref.watch(databaseProvider));
});

// ── 饮水 ──
final waterRepoProvider = Provider<WaterRepository>((ref) {
  return WaterRepositoryImpl(ref.watch(databaseProvider));
});

// ── 主题模式 ──
// 全站固定浅色主题，不再提供深色模式；保留 provider 仅为兼容初始化调用。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.light);

void initThemeMode(WidgetRef ref, {required String? themeMode}) {
  ref.read(themeModeProvider.notifier).state = ThemeMode.light;
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

  /// 当前激活的训练计划（首页「今日训练」）
  final PlanEntity? activePlan;

  /// 今天该练的动作（来自激活计划，dayOfWeek 匹配今天）
  final List<PlanDayEntity> todayPlanItems;

  /// 最早 / 最新身体照片（首页「身体变化」对比）
  final Photo? firstPhoto;
  final Photo? latestPhoto;

  /// 今天的身体照片（首页「今日图片」打卡）
  final Photo? todayPhoto;

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
    this.activePlan,
    this.todayPlanItems = const [],
    this.firstPhoto,
    this.latestPhoto,
    this.todayPhoto,
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
  final weighInDates = allMetrics
      .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
      .toSet();
  final todayCups = await waterRepo.getTodayCups();
  final weekWorkoutDays = recent
      .where((w) => !w.date.isBefore(monday))
      .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
      .toSet()
      .length;

  // 激活计划 + 今日排期（dayOfWeek: 0=周日 ... 6=周六）
  final plans = await ref.watch(planRepoProvider).getAll();
  final activePlans = plans.where((p) => p.isActive).toList();
  final activePlan = activePlans.isNotEmpty ? activePlans.first : null;
  final todayWeekday = now.weekday % 7;
  final todayPlanItems = activePlan == null
      ? const <PlanDayEntity>[]
      : activePlan.days.where((d) => d.dayOfWeek == todayWeekday).toList();

  // 最早 / 最新照片（仓储按 date desc 返回）
  final photos = await ref.watch(photoRepoProvider).getAll();
  final latestPhoto = photos.isNotEmpty ? photos.first : null;
  final firstPhoto = photos.isNotEmpty ? photos.last : null;
  final todayPhotos = photos
      .where((p) =>
          p.date.year == now.year &&
          p.date.month == now.month &&
          p.date.day == now.day)
      .toList();
  final todayPhoto = todayPhotos.isNotEmpty ? todayPhotos.first : null;

  return DashboardData(
    calendarWorkoutDates: calWorkouts
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet(),
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
    activePlan: activePlan,
    todayPlanItems: todayPlanItems,
    firstPhoto: firstPhoto,
    latestPhoto: latestPhoto,
    todayPhoto: todayPhoto,
  );
});

// ── 提醒设置 ──

/// 训练历史（训练页「历史」分段 / 训练记录列表共用；保存训练后需 invalidate）
final workoutHistoryProvider = FutureProvider<List<WorkoutEntity>>(
    (ref) => ref.watch(workoutRepoProvider).getAll());

/// 目标列表（保存训练会推进频率目标，需刷新）
final goalListProvider = FutureProvider<List<GoalEntity>>(
    (ref) => ref.watch(goalRepoProvider).getAll());
final reminderEnabledProvider = StateProvider<bool>((ref) => false);
final reminderHourProvider = StateProvider<int>((ref) => 8);
final reminderMinuteProvider = StateProvider<int>((ref) => 0);

/// 从 UserSettings 初始化提醒状态
void initReminderState(WidgetRef ref,
    {bool enabled = false, int hour = 8, int minute = 0}) {
  ref.read(reminderEnabledProvider.notifier).state = enabled;
  ref.read(reminderHourProvider.notifier).state = hour;
  ref.read(reminderMinuteProvider.notifier).state = minute;
}
