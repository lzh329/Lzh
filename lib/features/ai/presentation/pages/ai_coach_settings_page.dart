import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';

/// 教练设定 —— 自由调教嘎教练
///
/// 风格三档 / 回复长度 / 自由度（temperature）/ 自定义约束增删
/// 改动即存库，下一条消息生效（system prompt 每轮重新构建）。
class AiCoachSettingsPage extends ConsumerStatefulWidget {
  const AiCoachSettingsPage({super.key});

  @override
  ConsumerState<AiCoachSettingsPage> createState() =>
      _AiCoachSettingsPageState();
}

class _AiCoachSettingsPageState extends ConsumerState<AiCoachSettingsPage> {
  String _style = 'guga';
  String _length = 'medium';
  double _temp = AiService.defaultTemperature;
  List<String> _constraints = [];
  bool _loaded = false;

  final _inputCtrl = TextEditingController();

  static const _presets = [
    '回答里不要出现我的具体体重数字',
    '推荐食物时给出具体克数',
    '先反问我一个问题再给建议',
    '不要用感叹号，语气平实一点',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await ref.read(userSettingsProvider.future);
    if (!mounted) return;
    setState(() {
      _style = s?.aiStyle ?? 'guga';
      _length = s?.aiReplyLength ?? 'medium';
      _temp = (s?.aiTemperature ?? AiService.defaultTemperature).clamp(0.3, 1.0);
      _constraints = AiCoachOptions.decodeConstraints(s?.aiConstraints);
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await ref.read(userSettingsRepoProvider).save(
          aiStyle: _style,
          aiReplyLength: _length,
          aiTemperature: _temp,
          aiConstraints: AiCoachOptions.encodeConstraints(_constraints),
        );
    ref.invalidate(userSettingsProvider);
  }

  void _addConstraint(String text) {
    final t = text.trim();
    if (t.isEmpty || _constraints.contains(t)) return;
    setState(() => _constraints = [..._constraints, t]);
    _inputCtrl.clear();
    _save();
  }

  void _removeConstraint(String text) {
    setState(() => _constraints = _constraints.where((e) => e != text).toList());
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('教练设定'), centerTitle: false),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const _SectionTitle('教练风格'),
                const SizedBox(height: 8),
                for (final s in AiCoachOptions.styles)
                  _StyleCard(
                    style: s,
                    selected: _style == s.key,
                    onTap: () {
                      setState(() => _style = s.key);
                      _save();
                    },
                  ),
                const SizedBox(height: 20),

                const _SectionTitle('回复长度'),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    for (final l in AiCoachOptions.lengths)
                      ButtonSegment(value: l.key, label: Text(l.label)),
                  ],
                  selected: {_length},
                  onSelectionChanged: (v) {
                    setState(() => _length = v.first);
                    _save();
                  },
                ),
                const SizedBox(height: 20),

                const _SectionTitle('自由度'),
                const SizedBox(height: 2),
                Text(
                  _temp <= 0.5
                      ? '偏稳定：严格守规矩，措辞更保守'
                      : (_temp >= 0.85
                          ? '偏灵活：更有梗、更即兴，话也会多一点'
                          : '均衡：规矩和发挥各占一半'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _temp,
                        min: 0.3,
                        max: 1.0,
                        divisions: 14,
                        label: _temp.toStringAsFixed(2),
                        onChanged: (v) => setState(() => _temp = v),
                        onChangeEnd: (_) => _save(),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        _temp.toStringAsFixed(2),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                const _SectionTitle('自定义约束'),
                const SizedBox(height: 6),
                const Text(
                  '每条一句话，加进去就会写进 system prompt，优先级最高。比如"别提体重数字"、"每次回答先问我一个问题"。',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: 10),
                if (_constraints.isEmpty)
                  const Text('还没有自定义约束',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textTertiary))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in _constraints)
                        InputChip(
                          label: Text(c, style: const TextStyle(fontSize: 12)),
                          onDeleted: () => _removeConstraint(c),
                          deleteIconColor: AppColors.danger,
                          backgroundColor: AppColors.surface,
                          side: const BorderSide(color: AppColors.border),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        textInputAction: TextInputAction.done,
                        onSubmitted: _addConstraint,
                        decoration: InputDecoration(
                          hintText: '写一条约束，比如：别跟我客套',
                          isDense: true,
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: AppColors.border),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _addConstraint(_inputCtrl.text),
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('常用约束（点一下直接加）',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _presets)
                      ActionChip(
                        label: Text(p, style: const TextStyle(fontSize: 12)),
                        backgroundColor: AppColors.background,
                        side: const BorderSide(color: AppColors.border),
                        onPressed: _constraints.contains(p)
                            ? null
                            : () => _addConstraint(p),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  '设定改完立刻保存，下一条消息生效。想让语气更准，建议先清空聊天记录再试。',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiary, height: 1.5),
                ),
              ],
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

/// 风格选择卡
class _StyleCard extends StatelessWidget {
  final AiCoachStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _StyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withAlpha(16) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(style.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(style.description,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
