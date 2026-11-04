import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 两态合一的空状态（参数化文案，T16 / T17）。
///
/// 文案红线：事实陈述 + 一个出口，不带"加油"、不追责 ——
/// 用户当天没练的原因可能是加班、生病、来月经，App 不知道就不该评价。
class WorkoutEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onStart;

  /// 主按钮下方的次按钮（「已练，记一笔」）—— 有就显示，没有就空
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const WorkoutEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onStart,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            onPressed: onStart,
            icon: const Icon(Icons.add, size: 20),
            label: Text(buttonLabel),
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                side: const BorderSide(color: AppColors.border),
              ),
              onPressed: onSecondary,
              icon: const Icon(Icons.edit_note, size: 18),
              label: Text(secondaryLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
