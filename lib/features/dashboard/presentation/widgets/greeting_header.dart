import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 首页问候区 —— 咕嘎头像 + 时间段问候 + 日期 + 连续打卡徽章（非卡片，直接排版）
class GreetingHeader extends StatelessWidget {
  final int streakDays;

  /// 咕嘎立绘（传入后显示圆形头像）
  final String? avatarAsset;

  /// 当前咕嘎形态名（拼接在问候语后，如"晚上好，肥咕嘎"）
  final String? gugaName;

  /// 用户自定义昵称（null / 空串 = 没设 → 回落咕嘎形态名）
  final String? nickname;

  /// 距升级提示（如"距升级 12.0 斤"）
  final String? upgradeHint;

  const GreetingHeader({
    super.key,
    this.streakDays = 0,
    this.avatarAsset,
    this.gugaName,
    this.nickname,
    this.upgradeHint,
  });

  static const _green = AppColors.primary;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 拼「问候语，称呼」；称呼为空时只返回问候语（不留空尾）
  static String greetingWithName(String greeting, String? name) {
    final n = name?.trim();
    if (n == null || n.isEmpty || n == 'null') return greeting;
    return '$greeting，$n';
  }

  static String greetingOf(DateTime now) {
    final h = now.hour;
    if (h < 6) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateLabel =
        '${now.month}月${now.day}日 · 周${_weekdays[now.weekday - 1]}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (avatarAsset != null) ...[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: _green.withAlpha(90), width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              avatarAsset!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // 称呼优先级：昵称 → 咕嘎形态名 → 什么都不加。
                // 三处都可能为空，所以拼之前必须过滤空串，
                // 否则会出现「下午好，」这种空尾（或更糟的「下午好，null」）。
                greetingWithName(greetingOf(now), nickname ?? gugaName),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
                // 带上咕嘎形态名（如"你好呀，小嘎 · 新手"）可能超一行，
                // 放宽到 2 行：截断成"你好呀，小…"比换行更伤
                maxLines: 2,
              ),
              const SizedBox(height: 3),
              Text(
                upgradeHint != null ? '$dateLabel · $upgradeHint' : dateLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
                // 带上咕嘎形态名（如"你好呀，小嘎 · 新手"）可能超一行，
                // 放宽到 2 行：截断成"你好呀，小…"比换行更伤
                maxLines: 2,
              ),
            ],
          ),
        ),
        if (streakDays > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _green.withAlpha(24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _green.withAlpha(110), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 13, color: _green),
                const SizedBox(width: 4),
                Text(
                  '连续 $streakDays 天',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryText,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
