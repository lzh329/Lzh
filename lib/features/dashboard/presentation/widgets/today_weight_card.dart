import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 首页「体重」卡 —— 大字 + 变化 + 目标进度 + 记录入口
class TodayWeightCard extends StatelessWidget {
  final double? currentJin;
  final double? weekChangeJin;
  final double? targetJin;
  final double progress;
  final DateTime? lastRecordedAt;
  final VoidCallback onRecord;
  final VoidCallback onTap;

  const TodayWeightCard({
    super.key,
    this.currentJin,
    this.weekChangeJin,
    this.targetJin,
    this.progress = 0,
    this.lastRecordedAt,
    required this.onRecord,
    required this.onTap,
  });

  static const _orange = Color(0xFFFF8A00);
  static const _green = Color(0xFF3DDC84);
  static const _red = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = weekChangeJin;
    final changeColor = change == null
        ? Colors.white54
        : (change < -0.05 ? _green : (change > 0.05 ? _red : Colors.white54));
    final remain = (targetJin != null && currentJin != null)
        ? (currentJin! - targetJin!).clamp(0.0, 999.0).toDouble()
        : null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('体重', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    lastRecordedAt != null
                        ? '${DateFormat('M月d日 HH:mm').format(lastRecordedAt!)} 记录'
                        : '今天还没记录',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currentJin?.toStringAsFixed(1) ?? '--.--',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('斤',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  if (change != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: changeColor.withAlpha(28),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${change < 0 ? '' : '+'}${change.toStringAsFixed(1)}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: changeColor),
                      ),
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onRecord,
                    style: TextButton.styleFrom(
                      foregroundColor: _orange,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('记录',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: Colors.white.withAlpha(16),
                  color: _orange,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remain != null
                    ? '离目标还差 ${remain.toStringAsFixed(1)} 斤'
                    : '还没有设置目标体重',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
