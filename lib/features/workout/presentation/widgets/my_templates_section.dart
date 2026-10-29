import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'template_cards.dart';

/// 「我的模板」区：默认展开，超过 2 个可收起。
class MyTemplatesSection extends StatefulWidget {
  final List<WorkoutTemplateEntity> templates;
  final bool starting;
  final ValueChanged<WorkoutTemplateEntity> onStart;
  final VoidCallback onCreate;
  final ValueChanged<WorkoutTemplateEntity> onEdit;

  const MyTemplatesSection({super.key,
    required this.templates,
    required this.starting,
    required this.onStart,
    required this.onCreate,
    required this.onEdit,
  });

  @override
  State<MyTemplatesSection> createState() => MyTemplatesSectionState();
}

class MyTemplatesSectionState extends State<MyTemplatesSection> {
  // 需求 #1：我的模板默认展开（用户来这里就是要点自己的模板）
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final list = widget.templates;
    final visible = _expanded ? list : list.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TemplateSectionHeader(
          title: '我的模板',
          trailing: list.isEmpty ? null : '${list.length} 个',
          trailingAction: list.length > 2
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: AppColors.primaryText,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(_expanded ? '收起' : '展开'),
                    ),
                    IconButton(
                      onPressed: widget.onCreate,
                      tooltip: '新建模板',
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      color: AppColors.primary,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                )
              : TextButton.icon(
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: AppColors.primaryText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          EmptyMineCard(onCreate: widget.onCreate)
        else
          ...visible.map(
            (t) => TemplateCard(
              template: t,
              starting: widget.starting,
              coverHeight: 92,
              onStart: () => widget.onStart(t),
              onEdit: () => widget.onEdit(t),
            ),
          ),
      ],
    );
  }
}
