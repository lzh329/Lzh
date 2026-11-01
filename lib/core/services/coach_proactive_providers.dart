import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/coach_proactive_scheduler.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/core/services/coach_workout_recap.dart';
import 'package:fittrack/core/services/notification_service.dart';

/// 通知落点（生产走 [NotificationService]；单测注入假实现）
final coachPushSinkProvider = Provider<CoachPushSink>((ref) {
  return NotificationCoachPushSink(NotificationService());
});

final coachWeeklyGeneratorProvider = Provider<CoachWeeklyGenerator>((ref) {
  return CoachWeeklyGenerator();
});

final weeklyFactLoaderProvider = Provider<WeeklyFactLoader>((ref) {
  return WeeklyFactLoader(
    workout: ref.watch(workoutRepoProvider),
    body: ref.watch(bodyMetricRepoProvider),
    settings: ref.watch(userSettingsRepoProvider),
  );
});

/// 主动消息的唯一入口（周消息）
final coachProactiveSchedulerProvider = Provider<CoachProactiveScheduler>((ref) {
  return CoachProactiveScheduler(
    repo: ref.watch(coachProactiveRepoProvider),
    facts: ref.watch(weeklyFactLoaderProvider),
    generator: ref.watch(coachWeeklyGeneratorProvider),
    push: ref.watch(coachPushSinkProvider),
    settings: ref.watch(userSettingsRepoProvider),
    overrides: ref.watch(dailyOverrideRepoProvider),
  );
});

/// 训练后点评（本地模板，不调模型）
final coachWorkoutRecapServiceProvider =
    Provider<CoachWorkoutRecapService>((ref) {
  return CoachWorkoutRecapService(
    repo: ref.watch(coachProactiveRepoProvider),
    settings: ref.watch(userSettingsRepoProvider),
  );
});

/// 首页「教练说」气泡：**本周有记录 + 未读 + 总开关开** 才返回非 null
///
/// 与 [coachLatestWeeklyProvider] 是两个口径（PRD 6.1 状态机）：
/// 气泡是"有未读才出现、读后消失"；教练页卡片是"保留至下次周消息"。
final coachUnreadWeeklyProvider =
    FutureProvider<CoachProactiveMessage?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!(settings?.coachProactiveEnabled ?? true)) return null;
  final weekStart = mondayOf(DateTime.now());
  final record =
      await ref.watch(coachProactiveRepoProvider).getWeekly(weekStart);
  if (record == null || record.seenAt != null) return null;
  return record;
});

/// 教练页顶部卡片：本周最新一条（已读也返回），仅受总开关约束
final coachLatestWeeklyProvider =
    FutureProvider<CoachProactiveMessage?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!(settings?.coachProactiveEnabled ?? true)) return null;
  return ref.watch(coachProactiveRepoProvider).getLatestWeekly();
});

/// 首页气泡里的训练后点评：今日未读的那一条（同日最多 1 条）
final coachUnreadRecapProvider =
    FutureProvider<CoachProactiveMessage?>((ref) async {
  final settings = await ref.watch(userSettingsProvider.future);
  if (!(settings?.coachProactiveEnabled ?? true)) return null;
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  final today = await ref.watch(coachProactiveRepoProvider).listKindBetween(
        kind: kRecapKind,
        from: dayStart,
        to: dayStart.add(const Duration(days: 1)),
      );
  for (final m in today) {
    if (m.seenAt == null) return m;
  }
  return null;
});

/// 启动 / 回前台钩子：一行调用。
///
/// 内部吞掉所有异常 —— 周消息生成可能触发一次模型调用（最长 15 秒），
/// 绝不能阻塞首帧，也不能因为一次失败就让 App 起不来。
Future<void> runCoachProactiveStartup(WidgetRef ref) async {
  try {
    await ref.read(coachProactiveSchedulerProvider).runStartup();
  } catch (_) {
    // 主动消息失败不影响启动
  }
}

/// 渲染即已读：写 `seen_at` + 撤掉已排的通知 + 刷新两个气泡 provider
Future<void> markCoachWeeklySeen(WidgetRef ref, int id) async {
  await ref.read(coachProactiveSchedulerProvider).markSeen(id);
  ref.invalidate(coachUnreadWeeklyProvider);
  ref.invalidate(coachLatestWeeklyProvider);
}

/// 点评气泡渲染即已读（不推送，只写库 + 刷新）
Future<void> markCoachRecapSeen(WidgetRef ref, int id) async {
  await ref.read(coachWorkoutRecapServiceProvider).markSeen(id);
  ref.invalidate(coachUnreadRecapProvider);
}
