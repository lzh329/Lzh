import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'template_cards.dart';

/// 「推荐模板」区：收起时显示前 2 个（原来收起态什么都不渲染）。
class RecommendedSection extends StatefulWidget {
  final List<WorkoutTemplateEntity> templates;
  final bool starting;
  final ValueChanged<WorkoutTemplateEntity> onStart;

  const RecommendedSection({
    super.key,
    required this.templates,
    required this.starting,
    required this.onStart,
  });

  @override
  State<RecommendedSection> createState() => RecommendedSectionState();
}

class RecommendedSectionState extends State<RecommendedSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final list = widget.templates;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TemplateSectionHeader(
          title: '推荐模板',
          trailing: '${list.length} 个',
          trailingAction: list.length > 3
              ? TextButton(
                  onPressed: () {
                    setState(() => _expanded = !_expanded);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_expanded ? '已展开全部模板' : '已收起'),
                        duration: const Duration(milliseconds: 600),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    minimumSize: const Size(72, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: AppColors.primaryText,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: Text(_expanded ? '收起' : '展开'),
                )
              : null,
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const TemplateHintCard(text: '该分类下暂无模板，换个分类试试')
        else
          // 收起态也要渲染：原来这里什么都不画，用户看到"推荐模板 12 个"
          // 下面却是空的（需求 #1 顺手修的现存 bug）。与我的模板区对齐，显示前 2 个。
          ...(_expanded ? list : list.take(2).toList()).map(
            (t) => TemplateCard(
              template: t,
              starting: widget.starting,
              coverHeight: 132,
              onStart: () => widget.onStart(t),
            ),
          ),
      ],
    );
  }
}
