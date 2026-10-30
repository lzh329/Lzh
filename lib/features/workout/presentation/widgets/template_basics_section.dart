import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_meta_chips.dart';

/// 模板基础信息区：名称 / 难度 / 预计时长 / 描述
///
/// **不再有「类型」选择器**：模板是力量还是有氧，由里面放了什么动作决定
/// （见 `deriveTemplateType`）。用户不需要理解"类型"这个抽象概念，
/// 他只知道"我要练什么"。
class TemplateBasicsSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;

  final String difficulty;
  final int minutes;

  final ValueChanged<String> onDifficulty;
  final ValueChanged<int> onMinutes;

  const TemplateBasicsSection({
    super.key,
    required this.nameCtrl,
    required this.descCtrl,
    required this.difficulty,
    required this.minutes,
    required this.onDifficulty,
    required this.onMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: nameCtrl,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '模板名称',
            hintText: '例如：周末燃脂',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 4),
        TemplateMetaChips(
          difficulties: kDifficultyOrder,
          difficulty: difficulty,
          onDifficulty: onDifficulty,
        ),
        const SizedBox(height: 14),
        ...[
          Row(
            children: [
              const TemplateSectionLabel('预计时长'),
              const Spacer(),
              Text('$minutes 分钟',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryText)),
            ],
          ),
          Slider(
            value: minutes.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$minutes 分钟',
            onChanged: (v) => onMinutes(v.round()),
          ),
        ],
        TextField(
          controller: descCtrl,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '一句话描述（可选）',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
