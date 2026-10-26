import 'package:flutter/material.dart';

import 'active_workout_style.dart';

/// 训练执行页加载态 / 空态占位视图（浅色背景 + 居中内容 + 左上关闭）。
class ActiveWorkoutPlaceholder extends StatelessWidget {
  /// 居中展示的文案
  final String label;

  /// true 显示进度圈（加载中），false 显示图标（空态）
  final bool isLoading;

  /// 空态图标
  final IconData icon;

  /// 左上关闭按钮回调
  final VoidCallback onClose;

  /// 关闭按钮 tooltip
  final String closeTooltip;

  const ActiveWorkoutPlaceholder({
    super.key,
    required this.label,
    required this.onClose,
    this.isLoading = true,
    this.icon = Icons.fitness_center,
    this.closeTooltip = '退出训练',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ActiveWorkoutStyle.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: onClose,
                tooltip: closeTooltip,
                color: ActiveWorkoutStyle.textPrimary,
                icon: const Icon(Icons.close),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          ActiveWorkoutStyle.green,
                        ),
                      ),
                    )
                  else
                    Icon(icon, size: 44, color: ActiveWorkoutStyle.border),
                  const SizedBox(height: 16),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ActiveWorkoutStyle.textSecondary,
                    ),
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
