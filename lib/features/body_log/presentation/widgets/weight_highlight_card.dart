import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/weight_bucket.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 体重关键指标高亮卡（替代原来的三宫格）
///
/// 四块信息，按"用户每天早上会看的那一眼"排序：
/// ① 当前体重（大字）+ 目标 + BMI
/// ② 本周变化 / 累计减重（两列对比）
/// ③ 预计达标日期（来自 [predictWeightTrend]，原来是一行小字，现在提到卡里）
///
/// 目标为 null 时：不显示"距目标还差 X"，也不显示达标预测，
/// 显示「未设目标」—— 不编一个 0kg 的目标出来。
class WeightHighlightCard extends StatelessWidget {
  final List<BodyMetricEntity> metrics;
  final UserSettingsEntity? settings;
  final DateTime? now;

  const WeightHighlightCard({
    super.key,
    required this.metrics,
    this.settings,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (metrics.isEmpty) return const SizedBox.shrink();

    final latest = metrics.last;
    final currentJin = latest.weightKg * 2;
    final targetKg = settings?.targetWeightKg;
    final targetJin = targetKg == null ? null : targetKg * 2;

    final firstJin = metrics.first.weightKg * 2;
    final totalLossJin = metrics.length >= 2 ? firstJin - currentJin : null;
    final weekChangeKg = weekChangeKgOf(metrics, now: now);

    final prediction = predictWeightTrend(metrics, targetKg: targetKg);

    final bmi = settings?.bmi(latest.weightKg);
    final bmiLabel = bmi == null
        ? null
        : UserSettingsEntity.bmiLevelLabels[UserSettingsEntity.bmiLevel(bmi)];

    String signedJin(double? v) {
      if (v == null) return '—';
      if (v.abs() < 0.05) return '0.0';
      return v > 0 ? '+${v.toStringAsFixed(1)}' : v.toStringAsFixed(1);
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  currentJin.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 36, fontWeight: FontWeight.w700, height: 1.0),
                ),
                const SizedBox(width: 5),
                Text('斤',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textTertiary)),
                if (bmi != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'BMI ${bmi.toStringAsFixed(1)} · $bmiLabel',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textTertiary),
                  ),
                ],
                const Spacer(),
                Text(
                  targetJin == null
                      ? '未设目标'
                      : '目标 ${targetJin.toStringAsFixed(1)} 斤',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: targetJin == null
                        ? AppColors.textTertiary
                        : AppColors.primary,
                    fontWeight:
                        targetJin == null ? FontWeight.w400 : FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(
                  context,
                  label: '本周变化',
                  // 单位统一用斤（与页面其他位置一致）；null = 7 天内没有更早的记录
                  value: weekChangeKg == null
                      ? '—'
                      : '${signedJin(weekChangeKg * 2)} 斤',
                  highlight: weekChangeKg != null && weekChangeKg < 0,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                ),
                _stat(
                  context,
                  label: '累计减重',
                  value: totalLossJin == null
                      ? '—'
                      : '${signedJin(-totalLossJin).replaceFirst('-', '')} 斤',
                  highlight: totalLossJin != null && totalLossJin > 0,
                ),
              ],
            ),
            if (targetJin != null && prediction != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  prediction.daysToTarget == null
                      ? '📈 按当前趋势（每周${prediction.direction} '
                          '${(prediction.slopePerWeek * 2).abs().toStringAsFixed(2)} 斤），'
                          '暂时算不出达标日期'
                      : '📈 按当前趋势（每周${prediction.direction} '
                          '${(prediction.slopePerWeek * 2).abs().toStringAsFixed(2)} 斤），'
                          '预计 ${prediction.daysToTarget} 天后达到目标体重',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(
    BuildContext context, {
    required String label,
    required String value,
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.success : AppColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// 便于 widget 内部调用、同时保持 domain 函数为唯一实现
double? weekChangeKgOf(List<BodyMetricEntity> metrics, {DateTime? now}) =>
    weekChangeKg(metrics, now: now);
