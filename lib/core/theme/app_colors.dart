import 'package:flutter/material.dart';

/// 全站唯一色彩来源（浅色主题）。
///
/// 所有页面 / 组件应优先引用这里的令牌，避免散落的硬编码色值。
/// 品牌主色保持「燃橙」[primary]，深色仅用于文字与橙色底上的前景色。
abstract final class AppColors {
  // ── 底色与容器 ──
  /// 页面底色（暖白）
  static const Color background = Color(0xFFF7F4F0);

  /// 卡片 / 弹层 / 导航栏
  static const Color surface = Color(0xFFFFFFFF);

  /// 输入框 / 次级容器 / 选中态底
  static const Color surfaceAlt = Color(0xFFF1ECE6);

  /// 更重的分隔块 / 占位
  static const Color surfaceMuted = Color(0xFFEAE3DA);

  // ── 描边 ──
  /// 卡片描边、分割线
  static const Color border = Color(0xFFE3D9CE);

  /// 强调描边
  static const Color borderStrong = Color(0xFFD5C8BA);

  // ── 文字 ──
  /// 主文字
  static const Color textPrimary = Color(0xFF1B1613);

  /// 次要文字
  static const Color textSecondary = Color(0xFF6B6158);

  /// 三级文字 / 占位提示（白卡上对比度 ≈4.9:1，勿再调浅）
  static const Color textTertiary = Color(0xFF7A6F65);

  // ── 品牌与语义色 ──
  /// 品牌橙（填充）
  static const Color primary = Color(0xFFFF8A00);

  /// 品牌橙文字（浅底上可读，对比度 ≈5:1）
  static const Color primaryText = Color(0xFFC2410C);

  /// 橙底上的字（深色，保证对比度）
  static const Color onPrimary = Color(0xFF1B1613);

  /// 体重下降 / 完成
  ///
  /// ⚠️ 此值配白字仅 3.3:1——若用作按钮/填充底色，前景必须用 [onPrimary] 深字。
  static const Color success = Color(0xFF16A34A);

  /// 热量 / 警示
  static const Color warning = Color(0xFFD97706);

  /// 饮水
  static const Color info = Color(0xFF0284C7);

  /// 饮水按钮（深一档，白字对比度 ≈5.9:1）
  static const Color infoStrong = Color(0xFF0369A1);

  /// 分析 / 报告
  static const Color analysis = Color(0xFF7C3AED);

  /// 上涨 / 删除
  static const Color danger = Color(0xFFDC2626);
}
