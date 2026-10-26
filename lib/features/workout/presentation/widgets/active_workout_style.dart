import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 训练执行页（Keep 训练中风格）统一视觉常量。
///
/// 仅承载颜色 / 圆角 / 字号等视觉 token，不含任何业务逻辑，
/// 供 `ActiveWorkoutHeader` / `ActiveWorkoutActionCard` /
/// `ActiveWorkoutFooter` 及页面本身复用，避免散落的魔法值。
class ActiveWorkoutStyle {
  const ActiveWorkoutStyle._();

  /// 页面底色：暖白
  static const Color background = AppColors.background;

  /// 卡片底色
  static const Color surface = AppColors.surface;

  /// 主色（按钮 / 计时数字 / 进度条）
  static const Color green = AppColors.primary;

  /// 休息态强调色
  static const Color orange = AppColors.warning;

  /// 结束 / 放弃 类操作
  static const Color danger = AppColors.danger;

  /// 主要文字
  static const Color textPrimary = AppColors.textPrimary;

  /// 辅助文字（12px 级别）
  static const Color textSecondary = AppColors.textSecondary;

  /// 更弱的辅助文字（10-11px 级别）
  static const Color textTertiary = AppColors.textTertiary;

  /// 细描边
  static const Color border = AppColors.border;

  /// 输入框底色
  static const Color inputFill = AppColors.surfaceAlt;

  /// 主区大卡片圆角
  static const double cardRadius = 20;

  /// 输入框 / 小控件圆角
  static const double controlRadius = 10;

  /// 头部与主区间距
  static const double gapSection = 16;

  /// 主区与输入区、输入区与底部按钮之间距
  static const double gapBlock = 12;
}
