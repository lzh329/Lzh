import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 体重趋势曲线卡（近 30 条记录）
class WeightChartCard extends StatelessWidget {
  final List<BodyMetricEntity> metrics; // 升序

  const WeightChartCard({super.key, required this.metrics});

  static const _green = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = metrics.length > 30
        ? metrics.sublist(metrics.length - 30)
        : metrics;
    final fmt = DateFormat('M/d');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('体重趋势', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (recent.length >= 2)
                  Text(
                    '${fmt.format(recent.first.date)} - ${fmt.format(recent.last.date)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (recent.length < 2)
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    '记录 2 条以上体重后显示曲线',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              )
            else
              SizedBox(height: 180, child: _chart(recent)),
          ],
        ),
      ),
    );
  }

  Widget _chart(List<BodyMetricEntity> recent) {
    final weights = recent.map((m) => m.weightKg).toList();
    final minW = weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.reduce((a, b) => a > b ? a : b);
    final padding = ((maxW - minW) * 0.2).clamp(0.2, 2.0);
    final interval = ((maxW - minW) / 3).clamp(0.5, 10.0).toDouble();
    final labelStep = (recent.length / 3).ceil();

    return LineChart(
      LineChartData(
        minY: minW - padding,
        maxY: maxW + padding,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.white.withAlpha(12),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: interval,
              getTitlesWidget: (v, meta) => Text(
                v.toStringAsFixed(1),
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if (i < 0 || i >= recent.length) return const SizedBox.shrink();
                if (i % labelStep != 0 && i != recent.length - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${recent[i].date.month}/${recent[i].date.day}',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < recent.length; i++)
                FlSpot(i.toDouble(), recent[i].weightKg),
            ],
            isCurved: true,
            curveSmoothness: 0.3,
            color: _green,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _green.withAlpha(26),
            ),
          ),
        ],
      ),
    );
  }
}
