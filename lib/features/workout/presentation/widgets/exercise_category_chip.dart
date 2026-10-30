import 'package:flutter/material.dart';

/// 动作库分类筛选 chip（自定义训练页用）
class ExerciseCategoryChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const ExerciseCategoryChip({
    super.key,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: value == selected,
        onSelected: (_) => onTap(value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
