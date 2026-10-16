import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 体重时间轴卡 —— 起点 → 现在 → 目标
class WeightTimelineCard extends StatelessWidget {
  final TrendsData data;

  const WeightTimelineCard({super.key, required this.data});

  static const _green = Color(0xFF66BB6A);
  static const _amber = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.hasWeight) return const SizedBox.shrink();

    final fmt = DateFormat('M/d');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('体重时间轴', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '从起始记录到目标体重',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 18),

            // ── 时间轴 ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Node(
                  date: fmt.format(data.startDate!),
                  value: data.startJin!.toStringAsFixed(1),
                  color: Colors.white54,
                  dotSize: 10,
                ),
                _Line(theme),
                _Node(
                  date: fmt.format(data.latestDate!),
                  value: data.currentJin!.toStringAsFixed(1),
                  color: _green,
                  dotSize: 14,
                  highlight: true,
                ),
                _Line(theme),
                _Node(
                  date: '目标',
                  value: data.targetJin != null
                      ? data.targetJin!.toStringAsFixed(1)
                      : '—',
                  color: _amber,
                  dotSize: 10,
                ),
              ],
            ),

            const SizedBox(height: 16),
            Container(height: 1, color: Colors.white.withAlpha(16)),
            const SizedBox(height: 12),

            // ── 两栏摘要 ──
            Row(
              children: [
                Expanded(
                  child: _Summary(
                    value: data.totalLossJin != null
                        ? '${data.totalLossJin! >= 0 ? '-' : '+'}${data.totalLossJin!.abs().toStringAsFixed(1)} 斤'
                        : '—',
                    label: '距离起始',
                    color: (data.totalLossJin ?? 0) > 0.05
                        ? _green
                        : Colors.white70,
                  ),
                ),
                Expanded(
                  child: _Summary(
                    value: data.remainingJin != null
                        ? '${data.remainingJin! > 0 ? '还差 ' : ''}${data.remainingJin!.abs().toStringAsFixed(1)} 斤'
                        : '—',
                    label: '距离目标',
                    color: _amber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Node extends StatelessWidget {
  final String date;
  final String value;
  final Color color;
  final double dotSize;
  final bool highlight;

  const _Node({
    required this.date,
    required this.value,
    required this.color,
    required this.dotSize,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: highlight ? color : Colors.transparent,
              border: Border.all(color: color, width: 2),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 18 : 16,
              fontWeight: FontWeight.w600,
              color: highlight ? Colors.white : Colors.white70,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            date,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final ThemeData theme;
  const _Line(this.theme);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(height: 2, color: Colors.white.withAlpha(24)),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Summary({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: color),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
        ),
      ],
    );
  }
}
