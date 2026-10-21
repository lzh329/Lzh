import 'package:flutter/material.dart';

import 'active_workout_style.dart';

/// 训练执行页底部固定操作区（Keep「训练中」风格）。
///
/// 主按钮（全宽 52 高、绿色黑字）+ 次按钮行（跳过动作 / 结束训练）。
/// 文案、图标、颜色与回调全部由页面按当前状态决定。
class ActiveWorkoutFooter extends StatelessWidget {
  /// 主按钮文案：完成本组 / 跳过休息 / 停止计时 / 下一个动作 / 完成训练
  final String primaryLabel;
  final IconData primaryIcon;
  final Color primaryColor;
  final VoidCallback onPrimary;

  /// 是否允许「跳过动作」
  final bool canSkipExercise;
  final VoidCallback onSkipExercise;
  final VoidCallback onFinishWorkout;

  const ActiveWorkoutFooter({
    super.key,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryColor,
    required this.onPrimary,
    required this.canSkipExercise,
    required this.onSkipExercise,
    required this.onFinishWorkout,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ActiveWorkoutStyle.background,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onPrimary,
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  icon: Icon(primaryIcon, size: 20),
                  label: Text(primaryLabel),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryButton(
                      label: '下一个动作',
                      onPressed: canSkipExercise ? onSkipExercise : null,
                      color: ActiveWorkoutStyle.textSecondary,
                      side: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SecondaryButton(
                      label: '结束训练',
                      onPressed: onFinishWorkout,
                      color: ActiveWorkoutStyle.danger,
                      side: false,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 次按钮行中的单个按钮（高 40）
class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool side;

  const _SecondaryButton({
    required this.label,
    required this.onPressed,
    required this.color,
    required this.side,
  });

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    const textStyle = TextStyle(fontSize: 12.5);

    if (side) {
      return SizedBox(
        height: 40,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: const BorderSide(color: ActiveWorkoutStyle.border),
            shape: shape,
            textStyle: textStyle,
          ),
          child: Text(label),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          shape: shape,
          textStyle: textStyle,
        ),
        child: Text(label),
      ),
    );
  }
}
