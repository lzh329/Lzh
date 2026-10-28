import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// hide DailyOverride：drift 生成的行类与 daily_override_repository 的实体同名，
// 本文件两处都要用（AppDatabase / DailyOverride），不隐藏会报 ambiguous_import。
import 'package:fittrack/core/database/database.dart' hide DailyOverride;
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
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/core/services/reminder_scheduler.dart';

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

/// 生病闸门：按天覆盖的策略入口（数据层 + 误报计数都在里面）。
final sickDayGateProvider = Provider<SickDayGate>((ref) {
  return SickDayGate(
    ref.watch(dailyOverrideRepoProvider),
    ref.watch(userSettingsRepoProvider),
  );
});

/// 本地通知的排期落点：生产走 [NotificationService]，单测注入假实现。
final reminderSinkProvider = Provider<ReminderSink>((ref) {
  return NotificationServiceSink(NotificationService());
});

/// 提醒排期（内含生病闸门）。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler(
    sink: ref.watch(reminderSinkProvider),
    gate: ref.watch(sickDayGateProvider),
  );
});

/// 今日热量目标 —— 全 App 唯一的「今日口径」（T03-B1 / B2 / B3）。
///
/// 顺序不能反：先取全局目标（null = 用户没设目标），再用闸门放宽。
/// 全局为 null 时返回 **null**，绝不用 0 兜 —— 0 是"真的设成了 0 千卡"，
/// 会被读成"App 把我的目标算成 0"，比显示「未设置」伤信任得多。
///
/// 所有页面只准读这一个 provider，不许各自再拼一遍
/// `userSettings.dailyCalorieTarget ?? 0`。参照仓库既有先例：DailyNutrition
/// 是「全 App 唯一的当日营养口径」，这里同理。
final todayCalorieTargetProvider = FutureProvider<int?>((ref) async {
  final base = (await ref.watch(userSettingsProvider.future))?.dailyCalorieTarget;
  if (base == null) return null;
  final override = await ref.watch(sickDayOverrideProvider.future);
  return SickDayGate.relaxCalorieTarget(
    base,
    override?.calorieTargetOverride,
  );
});

/// 今日生效的生病覆盖 —— 今日页横幅的唯一数据源。
///
/// 用 AsyncNotifier 而非 FutureProvider：apply / revoke 写库后立刻回读落 state，
/// 不等下次启动、也不靠 invalidate 计数器。null = 今天没有覆盖。
final sickDayOverrideProvider =
    AsyncNotifierProvider<SickDayOverrideNotifier, DailyOverride?>(
        SickDayOverrideNotifier.new);

class SickDayOverrideNotifier extends AsyncNotifier<DailyOverride?> {
  @override
  Future<DailyOverride?> build() async {
    return ref.watch(sickDayGateProvider).overrideFor(_today());
  }

  /// 生效 / 更新今日覆盖；只改传入的字段。
  ///
  /// `source` 非法（非 user / ai_health）时抛 ArgumentError：state 记为
  /// AsyncError，同时把异常继续抛给调用方（AI 工具路径需要知道没写成）。
  Future<void> apply({
    int? calorieTargetOverride,
    double? setsScale,
    bool? reminderPaused,
    required String source,
  }) {
    return _refresh(() => ref.read(sickDayGateProvider).apply(
          date: _today(),
          calorieTargetOverride: calorieTargetOverride,
          setsScale: setsScale,
          reminderPaused: reminderPaused,
          source: source,
        ));
  }

  /// 撤销今日覆盖，立刻回到「没有覆盖」的安全态（横幅随之消失）。
  Future<void> revoke() {
    return _refresh(() => ref.read(sickDayGateProvider).revoke(_today()));
  }

  /// 写库 → 回读 → 落 state。失败时 state 记 AsyncError 并继续抛给调用方。
  Future<void> _refresh(Future<void> Function() write) async {
    state = const AsyncLoading<DailyOverride?>();
    try {
      await write();
      state =
          AsyncData(await ref.read(sickDayGateProvider).overrideFor(_today()));
    } catch (e, st) {
      state = AsyncError<DailyOverride?>(e, st);
      rethrow;
    }
  }

  /// 只认「今天」：覆盖按天存储，昨天的数据不参与今日计算。
  DateTime _today() => DateTime.now();
}

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
