import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 对比页空态：不足两张照片时显示，并直接给「从相册导入」的动作
///
/// 空态里放可执行动作，比只写"至少需要两张"有用 —— 用户在这里卡住时
/// 唯一想做的事就是补一张照片。
class CompareEmptyState extends StatelessWidget {
  final VoidCallback onImport;

  const CompareEmptyState({super.key, required this.onImport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('身体对比')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.compare, size: 48, color: AppColors.borderStrong),
            const SizedBox(height: 14),
            Text('至少需要两张照片才能对比', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(
              '从相册导入一张，或去「身体相册」拍一张最早的照片',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('从相册导入'),
            ),
          ],
        ),
      ),
    );
  }
}
