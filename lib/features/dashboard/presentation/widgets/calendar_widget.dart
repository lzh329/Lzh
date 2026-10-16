import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 月历组件 — 一对一对应真实日历，可翻月，训练日+称重日双标记
class CalendarWidget extends StatefulWidget {
  final Set<DateTime> workoutDates;
  final Set<DateTime> weighInDates;
  final void Function(DateTime date)? onDayTap;

  const CalendarWidget({
    super.key,
    required this.workoutDates,
    this.weighInDates = const {},
    this.onDayTap,
  });

  @override
  State<CalendarWidget> createState() => _CalendarWidgetState();
}

class _CalendarWidgetState extends State<CalendarWidget> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  void _prevMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
    });
  }

  bool _isWorkoutDay(DateTime date) {
    return widget.workoutDates.any((d) =>
        d.year == date.year && d.month == date.month && d.day == date.day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final monthFmt = DateFormat('yyyy年M月');

    // 本月信息
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final firstWeekday = _currentMonth.weekday; // 1=周一 … 7=周日

    // 填充格子：周一 = 第 1 列
    final leadingDays = firstWeekday - 1;
    final totalCells = ((leadingDays + daysInMonth) / 7).ceil() * 7;

    final cells = <Widget>[];

    for (var i = 0; i < totalCells; i++) {
      final dayIndex = i - leadingDays + 1; // 1-based day of month
      final isCurrentMonth = dayIndex >= 1 && dayIndex <= daysInMonth;

      DateTime date;
      if (isCurrentMonth) {
        date = DateTime(_currentMonth.year, _currentMonth.month, dayIndex);
      } else if (dayIndex < 1) {
        // 上月填充
        final prevMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
        final prevDays = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
        date = DateTime(prevMonth.year, prevMonth.month, prevDays + dayIndex);
      } else {
        // 下月填充
        date = DateTime(_currentMonth.year, _currentMonth.month + 1, dayIndex - daysInMonth);
      }

      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final hasWorkout = _isWorkoutDay(date);
      final hasWeighIn = widget.weighInDates.any((d) =>
          d.year == date.year && d.month == date.month && d.day == date.day);

      cells.add(
        _CalendarCell(
          date: date,
          isToday: isToday,
          hasWorkout: hasWorkout,
          hasWeighIn: hasWeighIn,
          isCurrentMonth: isCurrentMonth,
          onTap: () => widget.onDayTap?.call(date),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // ── 月份导航 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _prevMonth,
                  tooltip: '上一月',
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.2, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    monthFmt.format(_currentMonth),
                    key: ValueKey(monthFmt.format(_currentMonth)),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextMonth,
                  tooltip: '下一月',
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── 星期头 ──
            Row(
              children: const ['一', '二', '三', '四', '五', '六', '日']
                  .map((w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),

            // ── 日期网格 ──
            ...List.generate(totalCells ~/ 7, (row) {
              final start = row * 7;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: cells.sublist(start, start + 7),
                ),
              );
            }),

            const SizedBox(height: 6),

            // ── 图例 ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary)),
                const SizedBox(width: 3),
                Text('训练', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(width: 12),
                Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green.withAlpha(180))),
                const SizedBox(width: 3),
                Text('称重', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 日历中的单个日期格子
class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final bool hasWorkout;
  final bool hasWeighIn;
  final bool isCurrentMonth;
  final VoidCallback? onTap;

  const _CalendarCell({
    required this.date,
    required this.isToday,
    required this.hasWorkout,
    this.hasWeighIn = false,
    required this.isCurrentMonth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 今日背景色
    final bgColor = isToday ? theme.colorScheme.primary : Colors.transparent;
    // 日期文字色
    Color textColor;
    if (isToday) {
      textColor = theme.colorScheme.onPrimary;
    } else if (!isCurrentMonth) {
      textColor = theme.colorScheme.outline.withAlpha(100);
    } else {
      textColor = theme.colorScheme.onSurface;
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    color: textColor,
                  ),
                ),
                // 底部标记行：训练 + 称重
                if (hasWorkout || hasWeighIn)
                  Positioned(
                    bottom: 1,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasWorkout)
                          Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isToday ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
                            ),
                          ),
                        if (hasWorkout && hasWeighIn) const SizedBox(width: 3),
                        if (hasWeighIn)
                          Container(
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: isToday ? theme.colorScheme.onPrimary.withAlpha(200) : Colors.green, width: 1.2),
                              color: Colors.transparent,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
