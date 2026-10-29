import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 个人档案顶部身份卡（本轮**只读**）
///
/// 头像与姓名的编辑是第 3 步的事，这里先只展示已有身体摘要，
/// 不放假按钮 —— 点不动的东西不该长得像能点。
class ProfileIdentityCard extends StatelessWidget {
  final UserSettingsEntity? settings;

  const ProfileIdentityCard({super.key, this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = settings;
    final height = s?.heightCm;
    final targetKg = s?.targetWeightKg;

    final summary = <String>[
      if (height != null) '身高 ${height.toStringAsFixed(0)}cm',
      if (targetKg != null) '目标 ${(targetKg * 2).toStringAsFixed(1)} 斤',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(28),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline,
                  size: 24, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('个人档案', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    summary.isEmpty ? '还没填身体信息' : summary.join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
