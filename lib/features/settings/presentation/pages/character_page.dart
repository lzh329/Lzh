import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 「我的形象」—— 3 张角色卡 + 勾选 + 「还差 X 斤 / 已全部解锁」（C18）。
///
/// 三个刻意的设计：
/// 1. **每张卡都是静态 PNG**，一个 state machine 都不起（R11）：同屏 3 个 controller
///    是中端机首帧掉到 30fps 以下的经典写法，而用户在这页停留通常 <10 秒。
/// 2. **没有"选形态"控件**（C8）：选的是角色，形态是减重成果的可视化 ——
///    能手动选就等于把这个功能作废。
/// 3. **照骗**：卡上写的是「当前样子」与该角色的下一档，**不承诺**形态与减重幅度的
///    对应关系（糯糯三张图不是同一画风，说多了就露馅）。
class CharacterPage extends ConsumerWidget {
  const CharacterPage({super.key, this.catalogOverride});

  /// 仅测试用：注入一份"立绘文件不存在"的角色定义，验证 C15 的
  /// 「素材缺失 → 该卡不可选中」这条分支。生产代码永远传 null（读注册表）。
  final List<CharacterDef>? catalogOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // "哪张卡被选中"读的是**用户的选择**，不是 `currentCharacterProvider` ——
    // 后者在素材缺失时会回落成咕嘎，用它判断会把咕嘎标成"当前"，误导用户。
    final selectedId = CharacterId.parse(
        ref.watch(userSettingsProvider).valueOrNull?.characterId);
    final loss = ref.watch(characterLossProvider).historyMaxLossJin;
    final catalog = catalogOverride ?? CharacterCatalog.all;

    return Scaffold(
      appBar: AppBar(title: const Text('我的形象'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // 页头说明（定稿文案，见 character_lines.dart）
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
            child: Text(
              kCharacterSlogan,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final def in catalog)
            _CharacterCard(
              def: def,
              selected: def.id == selectedId,
              // 每张卡都用**自己的**历史最大减重算自己的档位
              spec: CharacterCatalog.specOf(def, loss),
              onSelect: () => ref.read(characterSelectionProvider).select(def.id),
            ),
          const SizedBox(height: 8),
          if (kDebugMode)
            Center(
              child: Text(
                '动效：程序化（本期无 .riv）· 选中的是角色，不是样子',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary.withAlpha(200),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterCard extends StatefulWidget {
  final CharacterDef def;

  /// 是否是当前选中的角色
  final bool selected;

  /// 该角色在当前减重下的渲染描述（决定卡上显示哪个样子）
  final CharacterRenderSpec spec;

  final VoidCallback onSelect;

  const _CharacterCard({
    required this.def,
    required this.selected,
    required this.spec,
    required this.onSelect,
  });

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  /// 立绘解码失败 → 这张卡变「素材缺失」且**不可选中**（C15）
  bool _missing = false;

  CharacterDef get def => widget.def;
  bool get selected => widget.selected;
  CharacterRenderSpec get spec => widget.spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? def.accent : AppColors.border,
          width: selected ? 1.6 : 0.8,
        ),
      ),
      child: InkWell(
        // 点当前已选角色 = 无操作（不重复写库、不弹提示）
        // 素材缺失的卡也不可选中（选了只会看到占位，不如不给点）
        onTap: selected || _missing ? null : widget.onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 立绘（静态 PNG，不接 Rive） ──
              Container(
                width: 84,
                height: 104,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _Portrait(
                  spec: spec,
                  onMissing: () => setState(() => _missing = true),
                ),
              ),
              const SizedBox(width: 14),
              // ── 文案 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(def.name,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (selected)
                          _Badge(color: def.accent, label: '当前', icon: Icons.check),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      // 描述行：多形象角色的"解锁进度"必须**按状态算**，
                      // 写死「三个样子等你解锁」会和下面的「已经全部解锁」自相矛盾
                      // （装机实测问题 2）。单形象角色直接用她的 tagline（不提解锁）。
                      def.maxForm <= 1
                          ? def.cardTagline
                          : kFormsProgressLine(
                              totalForms: def.maxForm,
                              currentForm: spec.form,
                            ),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '当前样子：${spec.formName}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: def.accent,
                      ),
                    ),
                    // 状态行：只在"还有下一档"或"素材缺失"时出现。
                    // 满档 / 单形象都不再重复一句（描述行已经说清了）。
                    if (_missing) ...[
                      const SizedBox(height: 4),
                      const Text(
                        kMissingAssetPlaceholder,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.danger,
                          height: 1.4,
                        ),
                      ),
                    ] else if (!spec.isMaxForm && def.maxForm > 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        kRemainToNextForm(
                          spec.remainToNextJin ?? 0,
                          spec.nextFormName ?? '',
                        ),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 角色立绘（静态）。缺图时显示「素材缺失」且**不可选中**（C15）。
///
/// 这里用 `Image.asset` 的 errorBuilder 做兜底，而不是逐卡 `rootBundle.load`：
/// 前者只在真的解码失败时才走，后者会一次性把 3 张图全解码（7 张里就有一半）。
class _Portrait extends StatelessWidget {
  final CharacterRenderSpec spec;

  /// 解码失败回调（卡片据此变「素材缺失」并禁用点击）
  final VoidCallback onMissing;

  const _Portrait({required this.spec, required this.onMissing});

  @override
  Widget build(BuildContext context) {
    final asset = spec.imageAsset;
    if (asset == null) {
      return const Center(
        child: Text(kMissingAssetShort,
            style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) {
        debugPrint('形象页立绘缺失：$error');
        // errorBuilder 在 build 期间，回调推到帧末（卡片要 setState）
        SchedulerBinding.instance.addPostFrameCallback((_) => onMissing());
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(6),
            child: Text(
              kMissingAssetShort,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;

  const _Badge({required this.color, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
