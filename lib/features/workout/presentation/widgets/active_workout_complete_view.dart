import 'package:flutter/material.dart';

import 'active_workout_style.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 训练执行页完成态视图（保留原有庆祝动画与保存入口，
/// 外层统一为浅色背景 + 居中布局）。
class ActiveWorkoutCompleteView extends StatelessWidget {
  /// 动作总数
  final int exerciseCount;

  /// 已完成组数
  final int setCount;

  /// 点击保存训练记录（由页面负责落库与跳转）
  final VoidCallback onSave;

  /// 右上关闭（由页面确认）
  final VoidCallback onClose;

  const ActiveWorkoutCompleteView({
    super.key,
    required this.exerciseCount,
    required this.setCount,
    required this.onSave,
    required this.onClose,
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
              right: 4,
              child: IconButton(
                onPressed: onClose,
                tooltip: '退出',
                color: ActiveWorkoutStyle.textTertiary,
                icon: const Icon(Icons.close, size: 20),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.celebration,
                        size: 64,
                        color: ActiveWorkoutStyle.green,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '训练完成！',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: ActiveWorkoutStyle.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '共 $exerciseCount 个动作 · $setCount 组',
                        style: const TextStyle(
                          fontSize: 14,
                          color: ActiveWorkoutStyle.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: ActiveWorkoutStyle.green,
                            foregroundColor: AppColors.onPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(14),
                              ),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          icon: const Icon(Icons.save, size: 20),
                          label: const Text('保存训练记录'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
