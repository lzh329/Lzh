import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 趋势页「行为统计」卡 —— 今日热量 / 今日饮水 / 本周训练
///
/// 首页只保留任务，数值统计统一放这里。
class StatsSummaryCard extends StatelessWidget {
  final double? todayCalories;
  final int todayCups;
  final int weekWorkoutCount;
  final int weekWorkoutMinutes;

  const StatsSummaryCard({
    super.key,
    this.todayCalories,
    this.todayCups = 0,
    this.weekWorkoutCount = 0,
    this.weekWorkoutMinutes = 0,
  });

  static const _purple = AppColors.analysis;
  static const _yellow = AppColors.warning;
  static const _blue = AppColors.info;
  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _purple.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.bar_chart, size: 15, color: _purple),
                ),
                const SizedBox(width: 10),
                Text('行为统计', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '今日 · 本周',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Cell(
                  label: '今日热量',
                  value:
                      todayCalories != null ? '${todayCalories!.round()}' : '—',
                  unit: 'kcal',
                  color: _yellow,
                ),
                const _Divider(),
                _Cell(
                  label: '今日饮水',
                  value: '$todayCups',
                  unit: '杯',
                  color: _blue,
                ),
                const _Divider(),
                _Cell(
                  label: '本周训练',
                  value: '$weekWorkoutCount',
                  unit: weekWorkoutMinutes > 0
                      ? '次 · $weekWorkoutMinutes 分'
                      : '次',
                  color: _orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _Cell({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontSize: 10, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  unit,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontSize: 9.5, color: AppColors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppColors.border,
    );
  }
}
