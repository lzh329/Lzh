import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 目标进度环卡片 —— 首页的视觉主角
///
/// 环形展示"从起始体重到目标"的完成度，中心显示还差多少斤
class TargetRingCard extends StatelessWidget {
  final double? startJin; // 起始体重（斤）
  final double? currentJin; // 当前体重（斤）
  final double? targetJin; // 目标体重（斤）
  final int? daysToTarget;
  final VoidCallback? onTap;

  const TargetRingCard({
    super.key,
    this.startJin,
    this.currentJin,
    this.targetJin,
    this.daysToTarget,
    this.onTap,
  });

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 无目标或体重 → 引导态
    if (targetJin == null || currentJin == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _green.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.flag, size: 20, color: _green),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('设定目标体重', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '有了目标，才能看到自己走了多远',
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
        ),
      );
    }

    final remaining = currentJin! - targetJin!;
    final reached = remaining <= 0;
    final progress = _calcProgress(reached);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ── 环形 ──
              SizedBox(
                width: 118,
                height: 118,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 光晕
                    Container(
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _green.withAlpha(reached ? 60 : 26),
                            _green.withAlpha(0),
                          ],
                        ),
                      ),
                    ),
                    CustomPaint(
                      size: const Size(118, 118),
                      painter: _RingPainter(progress: progress),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          reached
                              ? '达成'
                              : '还差',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reached
                              ? '✓'
                              : remaining.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: reached ? 28 : 22,
                            fontWeight: FontWeight.bold,
                            color: _green,
                            height: 1.1,
                          ),
                        ),
                        if (!reached)
                          Text(
                            '斤',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              // ── 详情 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('目标进度', style: theme.textTheme.titleSmall),
                        const Spacer(),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(
                      label: '起始',
                      value: startJin != null
                          ? '${startJin!.toStringAsFixed(1)} 斤'
                          : '—',
                    ),
                    const SizedBox(height: 5),
                    _InfoRow(
                      label: '当前',
                      value: '${currentJin!.toStringAsFixed(1)} 斤',
                      valueColor: Colors.white,
                    ),
                    const SizedBox(height: 5),
                    _InfoRow(
                      label: '目标',
                      value: '${targetJin!.toStringAsFixed(1)} 斤',
                      valueColor: _green,
                    ),
                    if (!reached && daysToTarget != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '按当前趋势约 $daysToTarget 天后达成',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFFA726),
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
    );
  }

  double _calcProgress(bool reached) {
    if (reached) return 1;
    final start = startJin;
    final target = targetJin!;
    final current = currentJin!;
    if (start == null || start <= target) {
      // 无起始基准：用"距目标的相对进度"兜底（每 20 斤视作满环）
      final span = math.max(20.0, (current - target));
      return ((span - (current - target)) / span).clamp(0.0, 1.0);
    }
    final total = start - target;
    final done = start - current;
    return (done / total).clamp(0.0, 1.0);
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;

    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(20);
    canvas.drawCircle(center, radius, bgPaint);

    if (progress <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    // 绿色渐变弧
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Color(0xFF66BB6A), Color(0xFF9CCC65)],
      ).createShader(rect);

    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.white70,
          ),
        ),
      ],
    );
  }
}
