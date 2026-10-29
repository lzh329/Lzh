import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// "我的"页顶部个人资料卡
///
/// 展示头像位、身高摘要与三项核心数据（当前体重 / 目标体重 / BMI）
class ProfileHeaderCard extends StatelessWidget {
  final UserSettingsEntity? settings;
  final double? currentWeightKg;
  final VoidCallback? onTap;

  const ProfileHeaderCard({
    super.key,
    this.settings,
    this.currentWeightKg,
    this.onTap,
  });

  static const _green = AppColors.primary;

  /// 默认称呼（用户没设昵称时用）
  static const defaultDisplayName = '减肥嘎用户';

  /// 展示名：昵称 trim 后非空 → 昵称；否则默认名。**不会渲染 null/空**
  String get displayName {
    final n = settings?.nickname?.trim();
    return (n == null || n.isEmpty || n == 'null') ? defaultDisplayName : n;
  }

  /// 头像文件：路径存在且文件可读 → File；否则 null（走占位）
  File? get avatarFile {
    final path = settings?.avatarPath;
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    return f.existsSync() ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heightCm = settings?.heightCm;
    final targetJin =
        settings?.targetWeightKg != null ? settings!.targetWeightKg! * 2 : null;
    final currentJin = currentWeightKg != null ? currentWeightKg! * 2 : null;
    final bmi = (currentWeightKg != null && settings != null)
        ? settings!.bmi(currentWeightKg!)
        : null;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // 右上角氛围光斑
            Positioned(
              right: -46,
              top: -56,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_green.withAlpha(46), _green.withAlpha(0)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _green.withAlpha(36),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _green.withAlpha(90),
                            width: 1,
                          ),
                          image: avatarFile == null
                              ? null
                              : DecorationImage(
                                  image: FileImage(avatarFile!),
                                  fit: BoxFit.cover,
                                  // 文件在但已损坏 → 保持占位底色，不红屏
                                  onError: (_, __) {},
                                ),
                        ),
                        child: avatarFile == null
                            ? const Icon(Icons.person_outline,
                                color: _green, size: 24)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              // 昵称（trim 后非空）→ 否则默认名。
                              // 原来这里硬编码 '减肥嘎用户'，用户设了昵称也不显示。
                              displayName,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              heightCm != null
                                  ? '身高 ${heightCm.toStringAsFixed(0)} cm · 完善资料让建议更准'
                                  : '完善身体信息，获得更准的减脂建议',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          size: 20, color: AppColors.textTertiary),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Metric(
                        value: currentJin != null
                            ? currentJin.toStringAsFixed(1)
                            : '—',
                        unit: '斤',
                        label: '当前体重',
                        color: AppColors.textPrimary,
                      ),
                      _vDivider(),
                      _Metric(
                        value: targetJin != null
                            ? targetJin.toStringAsFixed(1)
                            : '—',
                        unit: '斤',
                        label: '目标体重',
                        color: AppColors.primaryText,
                      ),
                      _vDivider(),
                      _Metric(
                        value: bmi != null ? bmi.toStringAsFixed(1) : '—',
                        unit: '',
                        label: 'BMI',
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 用留白代替竖线：更现代，也避免细线被 Flutter 调试叠加层（Debug Paint）高亮成红线
  Widget _vDivider() => const SizedBox(width: 20);
}

class _Metric extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final Color color;

  const _Metric({
    required this.value,
    required this.unit,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: color),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
