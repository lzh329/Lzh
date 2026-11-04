import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/week_summary.dart';

/// 本周摘要（T11 / T12）：3 个数字 + 一个「看统计」出口。
///
/// 三个数字都是纯计算（`WeekSummaryCalc`），不落库、不加表 —— 本周 4 次这类
/// 信息一旦持久化，就会和 `workouts` 打架（COACH-PRD 决策 5 的老教训）。
///
/// 图表**不放在这里**：记录页要回答"某天练了什么"，图表在 `/workout/stats`，
/// 两个页面各管一件事。
class WorkoutWeekSummary extends StatelessWidget {
  final WeekSummary summary;

  /// 「看统计」出口；null 时按钮不显示（组件被复用在别处时用）
  final VoidCallback? onViewStats;

  const WorkoutWeekSummary({
    super.key,
    required this.summary,
    this.onViewStats,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = onViewStats ?? () => context.push('/workout/stats');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          _Metric(value: '${summary.weekCount}', unit: '次', label: '本周训练'),
          const SizedBox(width: 10),
          const _Divider(),
          const SizedBox(width: 10),
          _Metric(
              value: '${summary.weekMinutes}', unit: '分钟', label: '本周时长'),
          const SizedBox(width: 10),
          const _Divider(),
          const SizedBox(width: 10),
          _Metric(value: '${summary.streakWeeks}', unit: '周', label: '连续训练'),
          const Spacer(),
          TextButton(
            onPressed: stats,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(
              '看统计',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String unit;
  final String label;

  const _Metric({
    required this.value,
    required this.unit,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 0.8, height: 26, color: AppColors.border);
}
