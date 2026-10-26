import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 趋势页「打卡日历」—— 最近 12 周的训练/称重热力图（GitHub 风格）
///
/// 一列 = 一周（周一 → 周日），从左到右时间递增：
/// - 橙色块 = 当天完成了训练
/// - 浅橙块 = 当天只称了体重
/// - 灰块   = 无记录
/// 今天有描边高亮，标题给出累计训练天数与当前连续打卡天数。
class WorkoutHeatmapCard extends StatelessWidget {
  final Set<DateTime> workoutDates;
  final Set<DateTime> weighInDates;

  static const _weeks = 12;

  const WorkoutHeatmapCard({
    super.key,
    required this.workoutDates,
    required this.weighInDates,
  });

  /// 当前连续训练天数（今天或昨天为终点，往前数连续有训练的天数）
  int get _streak {
    final today = DateTime.now();
    var cursor = DateTime(today.year, today.month, today.day);
    if (!workoutDates.contains(cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!workoutDates.contains(cursor)) return 0;
    }
    var streak = 0;
    while (workoutDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);

    // 本周周一往前推 (weeks-1) 周，得到网格起点（周一）
    final thisMonday = todayMid.subtract(Duration(days: todayMid.weekday - 1));
    final start = thisMonday.subtract(const Duration(days: 7 * (_weeks - 1)));

    final dayCount = workoutDates.length;

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
                    color: AppColors.primary.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month,
                      size: 15, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Text('打卡日历', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '最近 12 周 · 累计 $dayCount 天'
                  '${_streak > 0 ? ' · 连续 $_streak 天' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 星期标签列 + 12 周网格
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _WeekdayLabels(),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      for (var w = 0; w < _weeks; w++)
                        Expanded(
                          child: _WeekColumn(
                            start: start.add(Duration(days: 7 * w)),
                            today: todayMid,
                            workoutDates: workoutDates,
                            weighInDates: weighInDates,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 图例
            Row(
              children: [
                const _LegendDot(color: AppColors.surfaceMuted, label: '无记录'),
                const SizedBox(width: 12),
                _LegendDot(color: AppColors.primary.withAlpha(80), label: '称重'),
                const SizedBox(width: 12),
                const _LegendDot(color: AppColors.primary, label: '完成训练'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  static const _labels = ['一', '', '三', '', '五', '', '日'];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < 7; i++)
          SizedBox(
            height: 16,
            child: _labels[i].isEmpty
                ? null
                : Text(
                    _labels[i],
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: AppColors.textTertiary,
                      height: 1,
                    ),
                  ),
          ),
      ],
    );
  }
}

class _WeekColumn extends StatelessWidget {
  final DateTime start; // 本列周一
  final DateTime today;
  final Set<DateTime> workoutDates;
  final Set<DateTime> weighInDates;

  const _WeekColumn({
    required this.start,
    required this.today,
    required this.workoutDates,
    required this.weighInDates,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var d = 0; d < 7; d++)
          Container(
            width: double.infinity,
            height: 16,
            margin: const EdgeInsets.symmetric(vertical: 1),
            child: _DayCell(
              date: start.add(Duration(days: d)),
              today: today,
              workoutDates: workoutDates,
              weighInDates: weighInDates,
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final DateTime today;
  final Set<DateTime> workoutDates;
  final Set<DateTime> weighInDates;

  const _DayCell({
    required this.date,
    required this.today,
    required this.workoutDates,
    required this.weighInDates,
  });

  @override
  Widget build(BuildContext context) {
    final isFuture = date.isAfter(today);
    final hasWorkout = workoutDates.contains(date);
    final hasWeighIn = weighInDates.contains(date);
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;

    Color fill;
    if (hasWorkout) {
      fill = AppColors.primary;
    } else if (hasWeighIn) {
      fill = AppColors.primary.withAlpha(80);
    } else if (isFuture) {
      fill = AppColors.surface.withAlpha(0);
    } else {
      fill = AppColors.surfaceMuted;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(3.5),
        border: isToday
            ? Border.all(color: AppColors.textPrimary, width: 1.4)
            : null,
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}
