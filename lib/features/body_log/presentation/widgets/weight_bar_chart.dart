import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/weight_bucket.dart';

/// 体重分组柱状统计（替代原来的折线图）
///
/// 每期两根柱：**期平均**（主色实心）与**期最低**（浅色），目标体重画一条
/// 水平虚线。三条信息放在一张图里，用户不用来回切换就能看出
/// "这周平均多少 / 最低到过多少 / 离目标还差多少"。
///
/// 目标为 null 时**不画基准线**，也不显示"0kg"这种假数据 —— 没设目标就是
/// 没设，画一条 0 的线比不画更糟（用户会以为目标是 0kg）。
class WeightBarChart extends StatelessWidget {
  final List<WeightBucket> buckets;

  /// 目标体重（kg）；null = 未设目标
  final double? targetKg;

  const WeightBarChart({
    super.key,
    required this.buckets,
    this.targetKg,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('这段时间还没有体重记录',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
        ),
      );
    }

    final values = <double>[
      ...buckets.map((b) => b.avgKg),
      ...buckets.map((b) => b.minKg),
      if (targetKg != null) targetKg!,
    ];
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    // 上下各留一点空间，否则最高/最低柱会贴边、目标线可能压在边框上
    final pad = ((maxY - minY) * 0.15).clamp(0.5, 5.0);
    minY = (minY - pad).floorToDouble();
    maxY = (maxY + pad).ceilToDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 168,
          child: BarChart(
            BarChartData(
              minY: minY,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final b = buckets[group.x];
                    final name = rodIndex == 0 ? '平均' : '最低';
                    return BarTooltipItem(
                      '${b.label}\n$name ${rod.toY.toStringAsFixed(1)}kg',
                      const TextStyle(fontSize: 11, color: Colors.white),
                    );
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 100),
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppColors.border.withAlpha(120),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: ((maxY - minY) / 2).clamp(0.5, 100),
                    getTitlesWidget: (v, _) => Text(
                      v.toStringAsFixed(0),
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textTertiary),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final i = v.round();
                      if (i < 0 || i >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          buckets[i].label,
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.textTertiary),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              extraLinesData: targetKg == null
                  ? null
                  : ExtraLinesData(horizontalLines: [
                      HorizontalLine(
                        y: targetKg!,
                        color: AppColors.success,
                        strokeWidth: 1.5,
                        dashArray: const [5, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                          labelResolver: (_) =>
                              '目标 ${targetKg!.toStringAsFixed(1)}kg',
                        ),
                      ),
                    ]),
              barGroups: [
                for (var i = 0; i < buckets.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: buckets[i].avgKg,
                        width: buckets.length > 12 ? 5 : 9,
                        color: AppColors.primary,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                      BarChartRodData(
                        toY: buckets[i].minKg,
                        width: buckets.length > 12 ? 5 : 9,
                        color: AppColors.primary.withAlpha(70),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(2)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 图例：三个元素各代表什么，写清楚，不靠颜色猜
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(AppColors.primary, '期平均'),
            _legend(AppColors.primary.withAlpha(70), '期最低'),
            _legend(AppColors.success, '目标体重', dashed: true),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String label, {bool dashed = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dashed ? 14 : 8,
            height: dashed ? 2 : 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ],
      );
}
