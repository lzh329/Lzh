import 'package:flutter/material.dart';

import 'active_workout_style.dart';

/// 训练执行页中部主区大卡片（Keep「训练中」风格）。
///
/// 纯展示组件：动作名 / 目标 / 当前组状态大字 / 休息倒计时大字。
/// 所有数值、状态文案与回调都由页面计算后传入，卡片内不含业务逻辑。
class ActiveWorkoutActionCard extends StatelessWidget {
  /// 动作名称
  final String exerciseName;

  /// 目标文案，例如 `3 组 × 15 次`
  final String targetText;

  /// 状态文案，例如 `第 2 组 / 共 3 组`、`休息中`、`训练中`、`本动作已完成`
  final String statusText;

  /// 是否处于休息倒计时
  final bool isResting;

  /// 是否处于训练倒计时（自动模式）
  final bool isTraining;

  /// 当前动作所有组是否已完成
  final bool isLastSet;

  /// 是否为计时类动作（有氧 / 拉伸）
  final bool isTimed;

  /// 目标次数（可能为 null）
  final int? targetReps;

  /// 大字区域待展示的秒数（休息剩余 / 训练剩余 / 动作目标时长）
  final int displaySeconds;

  /// 点击「跳过休息」
  final VoidCallback onSkipRest;

  const ActiveWorkoutActionCard({
    super.key,
    required this.exerciseName,
    required this.targetText,
    required this.statusText,
    required this.isResting,
    required this.isTraining,
    required this.isLastSet,
    required this.isTimed,
    required this.targetReps,
    required this.displaySeconds,
    required this.onSkipRest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: ActiveWorkoutStyle.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(
          Radius.circular(ActiveWorkoutStyle.cardRadius),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                exerciseName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: ActiveWorkoutStyle.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                targetText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: ActiveWorkoutStyle.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                statusText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isResting
                      ? ActiveWorkoutStyle.orange
                      : ActiveWorkoutStyle.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              _buildMainValue(),
              if (isResting) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSkipRest,
                  style: TextButton.styleFrom(
                    foregroundColor: ActiveWorkoutStyle.textSecondary,
                    textStyle: const TextStyle(fontSize: 13),
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('跳过休息'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 大字区域：休息剩余 / 计时倒计时 / 目标次数 / 已完成
  Widget _buildMainValue() {
    if (isLastSet && !isResting && !isTraining) {
      return const Icon(
        Icons.check_circle_outline,
        size: 56,
        color: ActiveWorkoutStyle.green,
      );
    }

    final String value;
    final Color color;
    if (isResting) {
      value = _formatClock(displaySeconds);
      color = ActiveWorkoutStyle.orange;
    } else if (isTimed) {
      value = _formatClock(displaySeconds);
      color = ActiveWorkoutStyle.green;
    } else {
      value = '×${targetReps ?? '—'}';
      color = ActiveWorkoutStyle.textPrimary;
    }

    return Text(
      value,
      style: TextStyle(
        fontSize: isResting || isTimed ? 60 : 56,
        fontWeight: FontWeight.w700,
        height: 1.05,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// 秒 -> mm:ss（负数按 0 处理）
  String _formatClock(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (safe ~/ 60).toString().padLeft(2, '0');
    final seconds = (safe % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
