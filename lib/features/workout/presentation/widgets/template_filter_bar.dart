import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';

/// 训练页筛选栏：类型组（全部/力量/有氧）+ 难度组（全部/入门/中阶/高阶）
///
/// 两组都用**分段控件**（一个整体边框、内部按段平分、选中段填充主色）——
/// 产品决策：原来的「场景」维度删除，类型成为新的第一维度；
/// 两组形态统一，用户不需要辨认"哪种样式代表哪个维度"。
class TemplateFilterBar extends StatelessWidget {
  /// 类型筛选值（中文标签：全部/力量/有氧）
  final String type;
  final ValueChanged<String> onType;

  /// 难度组（固定三档 + 「全部」）；null = 不显示这一组
  final String? difficulty;
  final Map<String, int>? difficultyCounts;
  final ValueChanged<String>? onDifficulty;

  const TemplateFilterBar({
    super.key,
    required this.type,
    required this.onType,
    this.difficulty,
    this.difficultyCounts,
    this.onDifficulty,
  });

  @override
  Widget build(BuildContext context) {
    final difficulties = difficulty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 「场景」维度已整组删除（产品决策）：现在两组都是分段控件，
        // 第一组选类型、第二组选难度，形态统一、语义更清楚。
        TemplateFilterRow(
          label: '类型',
          trailing: _customButton(context),
          children: [
            SegmentedRow(
              options: const [kAllFilter, ...kTypeOrder],
              value: type,
              onSelect: onType,
            ),
          ],
        ),
        if (difficulties != null) ...[
          const SizedBox(height: 8),
          TemplateFilterRow(
            label: '难度',
            children: [
              // 难度组用**分段控件**，不是又一排 chip：
              // 两组都做成一排圆角 chip 时，深色底上只看得出实心/描边，
              // 用户根本分不清这是两个不同维度。一个整体边框 + 内部分隔线
              // 一眼就能看出"这是另一类选择"。
              // 难度：空档置灰（当前类型下 0 个模板）
              SegmentedRow(
                options: const [kAllFilter, ...kDifficultyOrder],
                value: difficulties,
                disabled: (v) =>
                    v != kAllFilter && (difficultyCounts?[v] ?? 0) == 0,
                onSelect: (v) => onDifficulty?.call(v),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 右侧「自定义」入口
  Widget _customButton(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: () => context.push('/workout/custom'),
        icon: const Icon(Icons.tune, size: 14),
        label: const Text('自定义',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          side: const BorderSide(color: AppColors.borderStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }
}

class TemplateFilterRow extends StatelessWidget {
  final String label;
  final List<Widget> children;
  final Widget? trailing;

  const TemplateFilterRow({
    super.key,
    required this.label,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: children),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 4), trailing!],
      ],
    );
  }
}

class DifficultyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const DifficultyChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textTertiary.withAlpha(110)
        : (selected ? AppColors.primary : AppColors.textSecondary);
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            // 描边 + 透明底：与场景组（实心底）一眼能分开
            color:
                selected ? AppColors.primary.withAlpha(14) : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class FocusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FocusChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected ? AppColors.primary.withAlpha(28) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 通用分段控件：一个整体圆角边框，内部按段平分，选中段填充主色
///
/// 类型组与难度组共用它 —— 形态统一，语义差异只体现在小标题上。
class SegmentedRow extends StatelessWidget {
  final List<String> options;
  final String value;

  /// 某一段是否置灰不可点（难度组的空档用）
  final bool Function(String option)? disabled;

  final ValueChanged<String> onSelect;

  const SegmentedRow({
    super.key,
    required this.options,
    required this.value,
    required this.onSelect,
    this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              _segment(options[i], showDivider: i > 0),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, {required bool showDivider}) {
    final enabled = !(disabled?.call(label) ?? false);
    final selected = value == label;
    final color = !enabled
        ? AppColors.textTertiary.withAlpha(110)
        : (selected ? AppColors.onPrimary : AppColors.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDivider)
          Container(width: 1, height: 22, color: AppColors.border),
        GestureDetector(
          onTap: enabled ? () => onSelect(label) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            color: selected ? AppColors.primary : Colors.transparent,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
