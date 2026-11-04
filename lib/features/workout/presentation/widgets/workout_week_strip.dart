import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_day_cell.dart';

/// 训练记录页的周日期条（T8）。
///
/// 从 `workout_list_page.dart` 的私有 `_WeekStrip` **原地搬家 + 提成公开类**，
/// 逻辑一个字没改：跨月翻周、同日双点、周一为起点这些边界代码是踩过坑的，
/// 重写等于重新踩一遍（PRD 决策 10 的反面论证）。
///
/// 图例（橙=训练 / 蓝=称重）也放在这里 —— 让记录页只剩 3 个块，
/// T-7 的「周条 < 摘要 < 明细」断言才干净。
class WorkoutWeekStrip extends StatelessWidget {
  /// 本周周一（00:00 归一化后的日期）
  final DateTime weekStart;

  /// 当前选中的日期
  final DateTime selected;

  /// 有训练的日期（已归一化到 `DateTime(y, m, d)`）
  final Set<DateTime> markedDates;

  /// 有称重的日期
  final Set<DateTime> weighDates;

  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const WorkoutWeekStrip({
    super.key,
    required this.weekStart,
    required this.selected,
    required this.markedDates,
    required this.weighDates,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
  });

  static const trainingDotColor = AppColors.warning;
  static const weighDotColor = AppColors.info;

  static const _labels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('M月d日');
    final end = weekStart.add(const Duration(days: 6));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一周',
                onPressed: onPrev,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${fmt.format(weekStart)} - ${fmt.format(end)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '选择日期查看当天训练',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一周',
                onPressed: onNext,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Builder(builder: (_) {
                    final d = weekStart.add(Duration(days: i));
                    // 归一化：集合里的键是 DateTime(y, m, d)，带时分的日期比不中
                    final day = DateTime(d.year, d.month, d.day);
                    return WorkoutDayCell(
                      date: d,
                      label: _labels[i],
                      selected: _sameDay(d, selected),
                      hasMark: markedDates.contains(day),
                      hasWeight: weighDates.contains(day),
                      onTap: () => onSelect(d),
                    );
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // 图例收进组件内部（T7：页面只剩三块）
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            WorkoutLegendDot(color: trainingDotColor, label: '训练'),
            SizedBox(width: 12),
            WorkoutLegendDot(color: weighDotColor, label: '称重'),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
