import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// AI 写库后的副作用：**统一刷新一组核心视图**。
///
/// 为什么不再按工具名逐个 `if`：历史上每加一个写工具都要记得补一条
/// `invalidate`，漏一次就出"记了看不到"的 bug（`log_workout` → 记录页
/// 不刷新，就是漏掉的那次）。本地 SQLite 查询很便宜，宁可多刷一组，
/// 也不让以后新增的写工具再踩同一个坑。
void applyAiToolSideEffects(Ref ref, AiToolCall call) {
  // 首页 / 趋势 / 目标 / 设置 / 训练记录 / 模板 / 动作库 / 身体记录
  // （后两个是"页面直接 watch 仓储"的数据源，重建后按新数据重新拉取）
  ref.invalidate(dashboardDataProvider);
  ref.invalidate(trendsDataProvider);
  ref.invalidate(goalListProvider);
  ref.invalidate(userSettingsProvider);
  ref.invalidate(workoutHistoryProvider);
  ref.invalidate(workoutTemplatesProvider);
  ref.invalidate(exerciseRepoProvider);
  ref.invalidate(bodyMetricRepoProvider);

  // 提醒开关：内存态要跟设置页实时对齐（不只是重查）
  if (call.name == AiToolSpecs.setReminder) {
    syncReminderState(ref, call.arguments);
  }

  // 清空全部数据：聊天记录也要失效（否则还能看到已删的对话）
  if (call.name == AiToolSpecs.wipeAllData) {
    ref.invalidate(aiChatRepoProvider);
    ref.read(reminderEnabledProvider.notifier).state = false;
  }
}

/// AI 改了提醒设置后，把内存里的开关状态同步过来（设置页实时反映）
void syncReminderState(Ref ref, Map<String, dynamic> args) {
  final enabled = AiToolArgs.boolOf(args['enabled']);
  if (enabled == null) return;
  ref.read(reminderEnabledProvider.notifier).state = enabled;
  final hour = AiToolArgs.optionalHour(args);
  final minute = AiToolArgs.optionalMinute(args);
  if (hour != null) ref.read(reminderHourProvider.notifier).state = hour;
  if (minute != null) ref.read(reminderMinuteProvider.notifier).state = minute;
}
