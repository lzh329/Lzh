import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';

/// 训练页筛选栏：场景组（实心 chip）+ 难度组（描边 chip，空档置灰）。
///
/// 两组视觉刻意不同：场景是可累积浏览的"频道"，难度是对同一批结果的收窄。
class TemplateFilterBar extends StatelessWidget {
  final List<String> filters;
  final String active;
  final ValueChanged<String> onSelect;

  /// 难度组（固定三档 + 「全部」）；null = 不显示这一组
  final String? difficulty;
  final Map<String, int>? difficultyCounts;
  final ValueChanged<String>? onDifficulty;

  const TemplateFilterBar({
    super.key,
    required this.filters,
    required this.active,
    required this.onSelect,
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
        TemplateFilterRow(
          label: '场景',
          trailing: _customButton(context),
          children: [
            for (final f in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FocusChip(
                  label: f,
                  selected: f == active,
                  onTap: () => onSelect(f),
                ),
              ),
          ],
        ),
        if (difficulties != null) ...[
          const SizedBox(height: 8),
          TemplateFilterRow(
            label: '难度',
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: DifficultyChip(
                  label: kAllFilter,
                  selected: difficulties == kAllFilter,
                  onTap: () => onDifficulty?.call(kAllFilter),
                ),
              ),
              for (final d in kDifficultyOrder)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: DifficultyChip(
                    label: d,
                    selected: difficulties == d,
                    // 当前场景下该档没有模板 → 置灰不可点（避免点了没结果）
                    enabled: (difficultyCounts?[d] ?? 0) > 0,
                    onTap: () => onDifficulty?.call(d),
                  ),
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
            style:
                const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
