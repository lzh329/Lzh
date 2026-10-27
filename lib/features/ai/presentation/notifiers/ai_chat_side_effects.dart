import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart'
    show workoutTemplatesProvider;

/// AI 写库后的副作用：刷新首页 / 趋势 / 目标 / 身体信息 / 动作库 / 模板
void applyAiToolSideEffects(Ref ref, AiToolCall call) {
  ref.invalidate(dashboardDataProvider);
  ref.invalidate(trendsDataProvider);
  ref.invalidate(goalListProvider);
  ref.invalidate(userSettingsProvider);
  if (call.name == AiToolSpecs.setReminder) {
    syncReminderState(ref, call.arguments);
  }
  if (call.name == AiToolSpecs.createExercise ||
      call.name == AiToolSpecs.createExercises) {
    // 动作库列表页直接 watch 仓储，重建后按新数据重新拉取
    ref.invalidate(exerciseRepoProvider);
  }
  if (call.name == AiToolSpecs.createTemplate) {
    // create_template 可能顺手新建了缺失动作（create_missing_exercises），
    // 所以动作库与训练页「模板」分段两个数据源都要刷新
    ref.invalidate(exerciseRepoProvider);
    ref.invalidate(workoutTemplatesProvider);
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
