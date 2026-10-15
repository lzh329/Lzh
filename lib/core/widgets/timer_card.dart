import 'package:flutter/material.dart';

/// 训练倒计时/休息倒计时卡片，支持编辑按钮
class TimerCard extends StatelessWidget {
  final String label;
  final int seconds;
  final bool isActive;
  final IconData icon;
  final Color color;
  final VoidCallback? onEdit;

  const TimerCard({
    super.key,
    required this.label,
    required this.seconds,
    required this.isActive,
    required this.icon,
    required this.color,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return Card(
      color: isActive ? color.withAlpha(20) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isActive ? color : theme.colorScheme.outline.withAlpha(40),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 16,
                    color: isActive ? color : theme.colorScheme.outline),
                const SizedBox(width: 4),
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive ? color : theme.colorScheme.outline,
                      fontWeight: isActive ? FontWeight.bold : null,
                    )),
                if (onEdit != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.edit,
                          size: 14, color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: isActive ? color : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
