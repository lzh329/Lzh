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
              // 难度组用**分段控件**，不是又一排 chip：
              // 两组都做成一排圆角 chip 时，深色底上只看得出实心/描边，
              // 用户根本分不清这是两个不同维度。一个整体边框 + 内部分隔线
              // 一眼就能看出"这是另一类选择"。
              DifficultySegmented(
                value: difficulties,
                counts: difficultyCounts ?? const {},
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

/// 难度分段控件：全部 / 入门 / 中阶 / 高阶
///
/// 与场景组的胶囊 chip 在**形态上**区分（不是靠颜色深浅）：
/// 一个整体圆角边框，内部按段平分，选中段填充主色、段间细分割线。
/// 空档（当前场景下 0 个模板）整段置灰不可点。
class DifficultySegmented extends StatelessWidget {
  final String value;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;

  const DifficultySegmented({
    super.key,
    required this.value,
    required this.counts,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final options = <String>[kAllFilter, ...kDifficultyOrder];
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
              _segment(
                options[i],
                showDivider: i > 0,
                enabled:
                    options[i] == kAllFilter || (counts[options[i]] ?? 0) > 0,
              ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label,
      {required bool showDivider, required bool enabled}) {
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
