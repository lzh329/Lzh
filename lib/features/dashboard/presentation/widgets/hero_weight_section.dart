import 'package:flutter/material.dart';

/// 首页 Hero 体重区 —— 大字排版 + 目标进度条（非卡片）
class HeroWeightSection extends StatelessWidget {
  final double? currentJin;
  final double? targetJin;
  final double progress; // 0..1
  final double? weekChangeJin; // 本周变化（负 = 下降）
  final int? daysToTarget;
  final VoidCallback? onTap;

  const HeroWeightSection({
    super.key,
    this.currentJin,
    this.targetJin,
    this.progress = 0,
    this.weekChangeJin,
    this.daysToTarget,
    this.onTap,
  });

  static const _green = Color(0xFF66BB6A);
  static const _amber = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (currentJin == null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _green.withAlpha(26),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.monitor_weight_outlined,
                    size: 22, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('记录第一条体重', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      '点击右下角「记录体重」开始你的减脂旅程',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      );
    }

    final remaining =
        targetJin != null ? (currentJin! - targetJin!).clamp(0.0, 999.0) : null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // 数字滚动
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: currentJin!),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text(
                  v.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '斤',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (weekChangeJin != null) ...[
                const SizedBox(width: 8),
                _ChangeTag(change: weekChangeJin!),
              ],
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
          if (targetJin != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white.withAlpha(16),
                color: _green,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  remaining != null && remaining > 0
                      ? '离目标还差 ${remaining.toStringAsFixed(1)} 斤'
                      : '目标达成',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (daysToTarget != null) ...[
                  Text(
                    ' · 预计 $daysToTarget 天后',
                    style: TextStyle(
                      fontSize: 11,
                      color: _amber.withAlpha(220),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeTag extends StatelessWidget {
  final double change;

  const _ChangeTag({required this.change});

  @override
  Widget build(BuildContext context) {
    final down = change < -0.05;
    final up = change > 0.05;
    final color = down
        ? const Color(0xFF66BB6A)
        : (up ? const Color(0xFFEF5350) : Colors.white54);
    final label = down
        ? '-${change.abs().toStringAsFixed(1)}'
        : (up ? '+${change.toStringAsFixed(1)}' : '0.0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label 本周',
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
