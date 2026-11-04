import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_week_strip.dart'
    show WorkoutWeekStrip;

/// 周日期条里的单个日期格 + 图例圆点（从 week_strip 抽出来守 200 行纪律）
class WorkoutDayCell extends StatelessWidget {
  final DateTime date;
  final String label;
  final bool selected;
  final bool hasMark;
  final bool hasWeight;
  final VoidCallback onTap;

  const WorkoutDayCell({
    super.key,
    required this.date,
    required this.label,
    required this.selected,
    required this.hasMark,
    required this.hasWeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const green = AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? green.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? green : AppColors.border,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? green : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? green : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasMark)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: WorkoutWeekStrip.trainingDotColor,
                      ),
                    ),
                  if (hasMark && hasWeight) const SizedBox(width: 3),
                  if (hasWeight)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: WorkoutWeekStrip.weighDotColor,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkoutLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const WorkoutLegendDot({
    super.key,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}
