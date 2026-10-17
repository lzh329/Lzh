import 'package:flutter/material.dart';
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

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final heightCm = settings?.heightCm;
    final targetJin =
        settings?.targetWeightKg != null ? settings!.targetWeightKg! * 2 : null;
    final currentJin =
        currentWeightKg != null ? currentWeightKg! * 2 : null;
    final bmi = (currentWeightKg != null && settings != null)
        ? settings!.bmi(currentWeightKg!)
        : null;

    return Material(
      color: const Color(0xFF121A13),
      borderRadius: BorderRadius.circular(18),
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
                        ),
                        child: const Icon(Icons.person_outline,
                            color: _green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '简瘦用户',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              heightCm != null
                                  ? '身高 ${heightCm.toStringAsFixed(0)} cm · 完善资料让建议更准'
                                  : '完善身体信息，获得更准的减脂建议',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: Colors.white54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          size: 20, color: theme.colorScheme.outline),
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
                        color: Colors.white,
                      ),
                      _vDivider(),
                      _Metric(
                        value:
                            targetJin != null ? targetJin.toStringAsFixed(1) : '—',
                        unit: '斤',
                        label: '目标体重',
                        color: _green,
                      ),
                      _vDivider(),
                      _Metric(
                        value: bmi != null ? bmi.toStringAsFixed(1) : '—',
                        unit: '',
                        label: 'BMI',
                        color: Colors.white70,
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

  Widget _vDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(width: 1, height: 28, color: Colors.white.withAlpha(20)),
      );
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
                      ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
