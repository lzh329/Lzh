import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 首页「今日训练」卡 —— 训练优先：今天该练什么 + 一键开始
class TodayTrainingCard extends StatelessWidget {
  /// 计划名（无计划时为 null）
  final String? planName;

  /// 今天排期标签（如「周三 · 今日排期」）
  final String? dayLabel;

  /// 今日动作摘要（如「深蹲 4 组」「硬拉 3 组」）
  final List<String> itemLabels;

  /// 是否有激活计划
  final bool hasPlan;

  /// 开始训练（有排期时）
  final VoidCallback onStart;

  /// 去选模板 / 管理计划（无排期时）
  final VoidCallback onBrowse;

  const TodayTrainingCard({
    super.key,
    this.planName,
    this.dayLabel,
    this.itemLabels = const [],
    this.hasPlan = false,
    required this.onStart,
    required this.onBrowse,
  });

  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasToday = hasPlan && itemLabels.isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _orange.withAlpha(80), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fitness_center,
                      size: 15, color: _orange),
                ),
                const SizedBox(width: 10),
                Text('今日训练', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  dayLabel ?? '未安排',
                  style: const TextStyle(
                      fontSize: 10,
                      color: _orange,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hasToday
                  ? (planName ?? '今日安排')
                  : (hasPlan ? '今天休息，好好恢复' : '还没有训练计划'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              hasToday
                  ? '${itemLabels.take(3).join(' · ')}${itemLabels.length > 3 ? ' 等 ${itemLabels.length} 个动作' : ''}'
                  : (hasPlan ? '想动一动？也可以直接选个模板' : '选一个模板，开始第一次训练'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary, height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: hasToday ? onStart : onBrowse,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: AppColors.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  hasToday ? Icons.play_arrow_rounded : Icons.search,
                  size: 20,
                ),
                label: Text(
                  hasToday ? '开始训练' : (hasPlan ? '选个模板' : '选一个模板'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
