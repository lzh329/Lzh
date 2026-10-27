import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 写操作确认卡 —— AI 想改数据时必须由你点头
///
/// 危险操作（删除类）走警示样式：红色边框 + 警示图标 + 「确认删除」，
/// 普通写记录保持橙色 + 「确认记录」。
class AiToolConfirmCard extends StatelessWidget {
  final AiToolPreview preview;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const AiToolConfirmCard({
    super.key,
    required this.preview,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final destructive = preview.isDestructive;
    final accent = destructive ? AppColors.danger : AppColors.primary;
    final titleColor =
        destructive ? AppColors.danger : AppColors.primaryText;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withAlpha(destructive ? 12 : 14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                destructive
                    ? Icons.warning_amber_rounded
                    : Icons.edit_note,
                size: 18,
                color: titleColor,
              ),
              const SizedBox(width: 6),
              Text(
                '嘎教练想${preview.label}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: titleColor),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(preview.detail,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          if (destructive) ...[
            const SizedBox(height: 4),
            const Text('删除后无法恢复',
                style: TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: const Text('取消')),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: onConfirm,
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                      )
                    : null,
                child: Text(destructive ? '确认删除' : '确认记录'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
