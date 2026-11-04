import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/workout_log_draft.dart';

/// 训练记录卡（T10）。
///
/// 字段口径全库只剩这一套：动作名（去重，` · ` 连接）+ `N 组` + 时长 + `HH:mm`。
/// 历史上训练页「历史」分段用的是 `N/M 组`（完成/总数），记录页用 `N 组` ——
/// 同一件事两种口径，所以那个分段整个删掉了（决策 12）。**不要再引入 N/M**。
/// 卡片上的「补记」轻标记（描边小字，不抢"训练组数"的视觉权重）
class _LogBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.info.withAlpha(90), width: 0.7),
      ),
      child: const Text(
        '补记',
        style: TextStyle(
          fontSize: 9.5,
          height: 1.3,
          color: AppColors.infoStrong,
        ),
      ),
    );
  }
}

class WorkoutRecordCard extends StatelessWidget {
  final WorkoutEntity workout;

  /// 动作 id → 名称
  final Map<int, String> exerciseNames;

  /// 点击（整卡可点，不放第二个按钮：两个右向元素指向两个行为会点错）
  final VoidCallback? onTap;

  const WorkoutRecordCard({
    super.key,
    required this.workout,
    required this.exerciseNames,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = AppColors.primary;

    // 动作名去重后连接（同一次训练可能同一动作多组）
    final names = workout.sets
        .map((s) => exerciseNames[s.exerciseId] ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(' · ');

    String? durationInfo;
    if (workout.durationSec != null) {
      final m = workout.durationSec! ~/ 60;
      final s = workout.durationSec! % 60;
      durationInfo = m > 0 ? '$m分$s秒' : '$s秒';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap ?? () => context.push('/workout/${workout.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: green.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center, size: 18, color: green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names.isEmpty ? '训练' : names,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${workout.sets.length} 组'
                            '${durationInfo != null ? ' · $durationInfo' : ''}'
                            ' · ${DateFormat('HH:mm').format(workout.date)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 「补记」轻标记：事后照着模板补的记录，与开练记录区分开。
                        // 判定用 type（来源字段），不用 note 暗号 —— note 是用户写的。
                        if (workout.type == WorkoutLogDraft.workoutType) ...[
                          const SizedBox(width: 6),
                          _LogBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
