import 'package:flutter/material.dart';

import 'package:fittrack/core/services/backup_candidate.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 二次确认：文案对比行数，空库候选给红色强警告（仍允许坚持）。
class RestoreConfirmDialog extends StatelessWidget {
  final RestorePreview preview;

  const RestoreConfirmDialog({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final hard = preview.hardWarning;
    return AlertDialog(
      title: const Text('确认恢复这份备份？'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(preview.summary),
            if (hard != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.danger.withAlpha(80)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        hard,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.danger,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            for (final note in preview.notes) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              '恢复开始前会先备份当前数据库；任何校验不通过都会中止，你的原数据不会被改动。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: preview.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(preview.destructive ? '仍要覆盖' : '恢复'),
        ),
      ],
    );
  }
}
