import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 「难度 / 部位」两组单选 chip（新建模板页用）
///
/// 纯展示 + 两个回调，状态留在页面。
class TemplateMetaChips extends StatelessWidget {
  final List<String> difficulties;
  final String difficulty;
  final ValueChanged<String> onDifficulty;
  final List<String> focuses;
  final String focus;
  final ValueChanged<String> onFocus;

  const TemplateMetaChips({
    super.key,
    required this.difficulties,
    required this.difficulty,
    required this.onDifficulty,
    required this.focuses,
    required this.focus,
    required this.onFocus,
  });

  @override
  Widget build(BuildContext context) {
    Widget group({
      required String label,
      required List<String> options,
      required String selected,
      required ValueChanged<String> onSelect,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8A8F98))),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: options
                .map((o) => ChoiceChip(
                      label: Text(o, style: const TextStyle(fontSize: 12)),
                      selected: selected == o,
                      onSelected: (_) => onSelect(o),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        group(
          label: '难度',
          options: difficulties,
          selected: difficulty,
          onSelect: onDifficulty,
        ),
        const SizedBox(height: 14),
        group(
          label: '部位',
          options: focuses,
          selected: focus,
          onSelect: onFocus,
        ),
      ],
    );
  }
}

/// 表单小节标题（「难度」「部位」「预计时长」共用）
class TemplateSectionLabel extends StatelessWidget {
  final String text;

  const TemplateSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.textTertiary)),
    );
  }
}
