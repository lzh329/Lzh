import 'package:flutter/material.dart';

/// 首页问候区 —— 时间段问候 + 日期 + 连续打卡徽章（非卡片，直接排版）
class GreetingHeader extends StatelessWidget {
  final int streakDays;

  const GreetingHeader({super.key, this.streakDays = 0});

  static const _green = Color(0xFF66BB6A);

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  static String greetingOf(DateTime now) {
    final h = now.hour;
    if (h < 6) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateLabel =
        '${now.month}月${now.day}日 · 周${_weekdays[now.weekday - 1]}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greetingOf(now),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            Text(
              dateLabel,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        const Spacer(),
        if (streakDays > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _green.withAlpha(24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green.withAlpha(110), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 13, color: _green),
                const SizedBox(width: 4),
                Text(
                  '连续 $streakDays 天',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _green,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
