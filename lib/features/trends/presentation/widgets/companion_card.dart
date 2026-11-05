import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 我的○○卡 —— 趋势页顶部
///
/// 左侧成长信息（样子名 / 进度 / 解锁提示），右侧圆形头像是**当前角色**的立绘。
///
/// 这里的措辞和趋势页其它地方刻意不同（见 C19 与风险 3）：
/// - 「累计减重 X 斤」= 起始 − 当前（趋势页口径）
/// - 「再减 X 斤，换下一个样子」= 起始 − 历史最低（形态口径）
/// 两个数字可能不一样，所以措辞必须不一样，否则用户会以为其中一个算错了。
class CompanionCard extends ConsumerWidget {
  final VoidCallback? onTap;

  const CompanionCard({super.key, this.onTap});

  static const _green = AppColors.primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 唯一渲染口径（C12）：角色 / 形态 / 台词池都从注册表来
    final spec = ref.watch(currentCharacterProvider);
    final loss = ref.watch(characterLossProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 左侧：成长信息 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sentiment_satisfied_alt,
                            size: 15, color: _green),
                        const SizedBox(width: 6),
                        // 「我的{角色名}」—— 名字只能来自注册表（C20）
                        Text('我的${spec.name}',
                            style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            // 形态名：只描述外观（C9）
                            spec.formName,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: spec.accent.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: spec.accent.withAlpha(110), width: 0.8),
                          ),
                          child: Text(
                            'Lv.${spec.form}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      // 台词（角色第一人称）与"教练的话"不是同一个说话人，
                      // 但这里展示的是角色状态，用第一句台词做状态描述
                      spec.linePool.isEmpty ? '' : spec.linePool.first,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _progressOf(spec),
                        minHeight: 5,
                        backgroundColor: AppColors.surfaceMuted,
                        color: spec.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      spec.isMaxForm
                          ? kAllFormsUnlocked
                          : kRemainToNextForm(
                              spec.remainToNextDays ?? 0,
                              spec.nextFormName ?? '',
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '累计减重 ${loss.currentLossJin.toStringAsFixed(1)} 斤',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // ── 右侧：圆形头像框（静态 PNG，不起 state machine，R11） ──
              Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceAlt,
                  border: Border.all(
                    color: spec.accent.withAlpha(90),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _Avatar(spec: spec),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 进度 = （已达档位 + 当前档内进度）÷ 最高档。
  ///
  /// 档内进度按**打卡天数**在本档区间里的位置算（阈值只从注册表读，
  /// 不在这里复制常量）。菲比只有 1 档 → 恒 1（她不会"变样子"）。
  double _progressOf(CharacterRenderSpec spec) {
    final def = CharacterCatalog.defOf(spec.id);
    final maxForm = def.maxForm;
    if (maxForm <= 1) return 1;
    final cur = def.forms[spec.form - 1].minCheckinDays;
    final next = spec.form >= maxForm ? cur : def.forms[spec.form].minCheckinDays;
    final span = next - cur;
    final inForm = (spec.form >= maxForm || span <= 0)
        ? 1.0
        : ((spec.checkinDays - cur) / span).clamp(0.0, 1.0);
    // clamp：满档时公式会算出 (2+1)/2 = 1.5，值本身 >1 是错的（QA 记的 D1）
    return (((spec.form - 1) + inForm) / (maxForm - 1)).clamp(0.0, 1.0);
  }
}

/// 头像：咕嘎有 `_head` 拆分图就用头，其它角色用整图（注册表决定）
class _Avatar extends StatelessWidget {
  final CharacterRenderSpec spec;

  const _Avatar({required this.spec});

  @override
  Widget build(BuildContext context) {
    // 有拆分图 → 用头（贴脸好看）；没有 → 整图（等比 cover 到顶部）
    final asset = spec.headAsset ?? spec.imageAsset;
    if (asset == null) {
      return const Icon(Icons.sentiment_satisfied_alt,
          size: 40, color: AppColors.textTertiary);
    }
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stack) {
        debugPrint('趋势页角色头像缺失：$error');
        return const Icon(Icons.sentiment_satisfied_alt,
            size: 40, color: AppColors.textTertiary);
      },
    );
  }
}
