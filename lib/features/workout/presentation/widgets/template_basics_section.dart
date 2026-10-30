import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_cardio_minutes_field.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_filter_bar.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_meta_chips.dart';

/// 模板基础信息区：名称 / 类型 / 难度 / 时长
///
/// 时长控件随类型切换：
/// - 力量 → 「预计时长」滑块 5~60（沿用旧交互）
/// - 有氧 → 「总时长（分钟）」数字输入 5~180（滑块拖不出 90 分钟，也看不出越界）
class TemplateBasicsSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descCtrl;

  /// strength / cardio
  final String type;
  final String difficulty;
  final int minutes;

  final ValueChanged<String> onType;
  final ValueChanged<String> onDifficulty;
  final ValueChanged<int> onMinutes;

  const TemplateBasicsSection({
    super.key,
    required this.nameCtrl,
    required this.descCtrl,
    required this.type,
    required this.difficulty,
    required this.minutes,
    required this.onType,
    required this.onDifficulty,
    required this.onMinutes,
  });

  bool get _isCardio => type == 'cardio';

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
        const TemplateSectionLabel('类型'),
        SegmentedRow(
          options: const ['力量', '有氧'],
          value: _isCardio ? '有氧' : '力量',
          onSelect: (v) => onType(v == '有氧' ? 'cardio' : 'strength'),
        ),
        TemplateMetaChips(
          difficulties: kDifficultyOrder,
          difficulty: difficulty,
          onDifficulty: onDifficulty,
        ),
        const SizedBox(height: 14),
        if (_isCardio)
          TemplateCardioMinutesField(minutes: minutes, onChanged: onMinutes)
        else ...[
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
