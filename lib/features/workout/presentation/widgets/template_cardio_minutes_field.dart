import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'template_edit_item.dart';
import 'template_meta_chips.dart';

/// 有氧模板的「总时长（分钟）」输入（5~180）
///
/// 为什么不复用力量那根滑块：滑块的上限是 5~60，而有氧动辄 45/90 分钟；
/// 更关键的是滑块**改不了小数、也看不出越界**，用户输入 300 时滑块会直接
/// 把他拖回 60 —— 那就是静默篡改。这里用数字输入 + 越界提示，让他自己改。
class TemplateCardioMinutesField extends StatefulWidget {
  final int minutes;
  final ValueChanged<int> onChanged;

  const TemplateCardioMinutesField({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  @override
  State<TemplateCardioMinutesField> createState() =>
      _TemplateCardioMinutesFieldState();
}

class _TemplateCardioMinutesFieldState
    extends State<TemplateCardioMinutesField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: '${widget.minutes}');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onInput(String raw) {
    final v = int.tryParse(raw.trim());
    if (v == null) {
      setState(() => _error = '请输入数字');
      return;
    }
    final err = cardioMinutesError(v);
    setState(() => _error = err);
    // 越界不写回上层：保留用户输入，让他自己改
    if (err == null) widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TemplateSectionLabel('总时长（分钟）'),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          onChanged: _onInput,
          decoration: InputDecoration(
            isDense: true,
            hintText: '默认 30，范围 $kCardioMinMinutes~$kCardioMaxMinutes',
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('有氧模板按总时长记录，动作可留空',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          ),
      ],
    );
  }
}
