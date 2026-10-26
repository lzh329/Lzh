import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

import 'active_workout_style.dart';

/// 训练执行页顶部自定义头部（Keep 训练中风格）。
///
/// 结构：左「关闭 X」 + 中「细进度条」 + 右「动作计数 3/10」，
/// 其下一行小字「第 N 个动作 · 共 M 个」。不使用 AppBar。
class ActiveWorkoutHeader extends StatelessWidget {
  /// 当前动作序号（0 基）
  final int currentIndex;

  /// 动作总数
  final int total;

  /// 整体进度 0.0 ~ 1.0
  final double progress;

  /// 点击关闭（由页面弹出确认退出）
  final VoidCallback onClose;

  /// 点击打开训练设置（计时 / 休息 / 节拍 / 语音）
  final VoidCallback? onSettings;

  /// 副标题（循环模式显示「第 X 轮 / 共 Y 轮 · 动作 3/4」）
  final String? roundText;

  const ActiveWorkoutHeader({
    super.key,
    required this.currentIndex,
    required this.total,
    required this.progress,
    required this.onClose,
    this.onSettings,
    this.roundText,
  });

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    final safeIndex = currentIndex < 0 ? 0 : currentIndex;
    final safeTotal = total < 1 ? 1 : total;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onClose,
                tooltip: '退出训练',
                iconSize: 22,
                color: ActiveWorkoutStyle.textPrimary,
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: safeProgress,
                    minHeight: 3,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      ActiveWorkoutStyle.green,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${safeIndex + 1}/$safeTotal',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: ActiveWorkoutStyle.textSecondary,
                ),
              ),
              if (onSettings != null)
                IconButton(
                  onPressed: onSettings,
                  tooltip: '训练设置',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  color: ActiveWorkoutStyle.textTertiary,
                  icon: const Icon(Icons.tune),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 2),
            child: Text(
              roundText ?? '第 ${safeIndex + 1} 个动作 · 共 $safeTotal 个',
              style: const TextStyle(
                fontSize: 11,
                color: ActiveWorkoutStyle.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
