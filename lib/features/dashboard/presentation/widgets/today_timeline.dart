import 'package:flutter/material.dart';

/// 时间线条目
class TimelineEntry {
  final String title;
  final String? subtitle;
  final Color color; // 实心点颜色（已完成）
  final bool done;

  const TimelineEntry({
    required this.title,
    this.subtitle,
    this.color = const Color(0xFF66BB6A),
    this.done = true,
  });
}

/// 今日动态 —— 时间线卡片
class TodayTimeline extends StatelessWidget {
  final List<TimelineEntry> entries;

  const TodayTimeline({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日动态', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '今天还没有记录，从一条体重开始吧',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              )
            else
              for (int i = 0; i < entries.length; i++)
                _TimelineRow(
                  entry: entries[i],
                  isLast: i == entries.length - 1,
                ),
          ],
        ),
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineEntry entry;
  final bool isLast;

  const _TimelineRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 圆点 + 连线
          SizedBox(
            width: 16,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.done ? entry.color : Colors.transparent,
                    border: entry.done
                        ? null
                        : Border.all(
                            color: Colors.white.withAlpha(60), width: 1.2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: Colors.white.withAlpha(18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 12 : 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: entry.done
                                ? Colors.white
                                : theme.colorScheme.outline,
                            fontSize: 13,
                          ),
                        ),
                        if (entry.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            entry.subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
