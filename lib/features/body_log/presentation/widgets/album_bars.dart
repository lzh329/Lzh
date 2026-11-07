import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 相册底部：对比选择条（选 2 张后开始对比）
class AlbumCompareBar extends StatelessWidget {
  final int picked;
  final VoidCallback onCompare;
  final VoidCallback onCancel;

  const AlbumCompareBar({
    super.key,
    required this.picked,
    required this.onCompare,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('已选 $picked/2',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary)),
          ),
          TextButton(onPressed: onCancel, child: const Text('取消')),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: picked == 2 ? onCompare : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.compare, size: 18),
            label: const Text('开始对比',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// 相册底部：批量选择条（删除 / 取消）
class AlbumSelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const AlbumSelectionBar({
    super.key,
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('已选 $count 张',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary)),
          ),
          TextButton(onPressed: onCancel, child: const Text('取消')),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: count == 0 ? null : onDelete,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
