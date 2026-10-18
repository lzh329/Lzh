import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 目标进度卡 —— "距离目标还差 X 斤" + 三宫格统计
class GoalProgressCard extends StatelessWidget {
  final TrendsData data;

  const GoalProgressCard({super.key, required this.data});

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!data.hasWeight) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              '记录第一条体重，开始追踪你的减脂趋势',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ),
      );
    }

    final remaining = data.remainingJin;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _green.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.flag, size: 16, color: _green),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    remaining != null && remaining > 0
                        ? '距离目标还差 ${remaining.toStringAsFixed(1)} 斤'
                        : '距离目标 —',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Text(
                data.startDate != null
                    ? '以 ${DateFormat('M月d日').format(data.startDate!)} 的 ${data.startJin!.toStringAsFixed(1)} 斤为起始基准，已记录 ${data.daysRecorded} 天'
                    : '',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withAlpha(16)),
            const SizedBox(height: 12),
            Row(
              children: [
                _Cell(
                  value: '${data.currentJin!.toStringAsFixed(1)}斤',
                  label: '当前',
                  color: Colors.white,
                ),
                _Cell(
                  value: '${data.workoutDays}天',
                  label: '锻炼日',
                  color: _green,
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
  final String value;
  final String label;
  final Color color;

  const _Cell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
