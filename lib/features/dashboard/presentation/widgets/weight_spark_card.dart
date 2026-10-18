import 'package:flutter/material.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 首页「体重趋势」迷你卡 —— 近 N 次记录的自绘折线（无第三方依赖）
class WeightSparkCard extends StatelessWidget {
  final List<BodyMetricEntity> metrics;
  final VoidCallback? onTap;

  const WeightSparkCard({super.key, required this.metrics, this.onTap});

  static const _green = Color(0xFF3DDC84); // 趋势线表达「下降 = 健康」
  static const _red = Color(0xFFEF5350);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = metrics.length > 7
        ? metrics.sublist(metrics.length - 7)
        : metrics;
    final jin = points.map((m) => m.weightKg * 2).toList();

    final delta = jin.length >= 2 ? jin.last - jin.first : null;
    final lineColor = delta == null
        ? Colors.white54
        : (delta < -0.05 ? _green : (delta > 0.05 ? _red : Colors.white54));

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _green.withAlpha(32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.show_chart,
                        size: 15, color: _green),
                  ),
                  const SizedBox(width: 10),
                  Text('体重趋势', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 6),
                  Text(
                    '近 ${points.length} 次',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
                  ),
                  const Spacer(),
                  if (delta != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: lineColor.withAlpha(28),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${delta < 0 ? '' : '+'}${delta.toStringAsFixed(1)} 斤',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: lineColor,
                        ),
                      ),
                    ),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 16, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 58,
                width: double.infinity,
                child: jin.length < 2
                    ? Center(
                        child: Text(
                          '再记录 ${2 - jin.length} 次就能看到趋势',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline, fontSize: 11),
                        ),
                      )
                    : CustomPaint(
                        painter: _SparkPainter(values: jin, color: lineColor),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.1 ? 1.0 : maxV - minV;
    final dx = size.width / (values.length - 1);
    const padTop = 6.0;
    final usableH = size.height - padTop - 4;

    double yOf(double v) => padTop + (1 - (v - minV) / span) * usableH;

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = yOf(values[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 渐变填充
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(46), color.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );

    // 折线
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // 末点
    final lastY = yOf(values.last);
    canvas.drawCircle(Offset(size.width, lastY), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
