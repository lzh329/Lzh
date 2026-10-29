import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 体重页的历史列表与迷你指标卡（纯展示，状态与取数在页面）
class BodyMiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const BodyMiniStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: color),
                  ),
                  Text(
                    ' 斤',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BodyHistoryRow extends StatelessWidget {
  final BodyMetricEntity metric;
  final Future<void> Function() onDelete;

  const BodyHistoryRow(
      {super.key, required this.metric, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 2),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  DateFormat('MM/dd').format(metric.date),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ),
              Text(
                (metric.weightKg * 2).toStringAsFixed(1),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 3),
              Text(
                '斤',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.textTertiary,
                onPressed: () => onDelete(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BodyPageData {
  final List<BodyMetricEntity> metrics;

  /// 只留张数：页面不再渲染照片网格，相册入口已移到「我的」页
  final int photoCount;

  const BodyPageData({this.metrics = const [], this.photoCount = 0});
}
