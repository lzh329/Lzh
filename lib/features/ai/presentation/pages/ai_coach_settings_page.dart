import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/core/services/web_tools_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_coach_settings_widgets.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_coach_presets.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_model_config_card.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

/// 教练设定 —— 自由调教嘎教练
///
/// 风格四档（豆包感 / 嘎式 / 温柔 / 严厉）/ 回复长度 / 自由度（temperature）
/// / 自定义约束增删。改动即存库，下一条消息生效（system prompt 每轮重新构建）。
class AiCoachSettingsPage extends ConsumerStatefulWidget {
  const AiCoachSettingsPage({super.key});

  @override
  ConsumerState<AiCoachSettingsPage> createState() =>
      _AiCoachSettingsPageState();
}

class _AiCoachSettingsPageState extends ConsumerState<AiCoachSettingsPage> {
  /// 默认风格跟随 AiCoachOptions.styles.first（当前是豆包感），避免两处写死不一致
  String _style = AiCoachOptions.styleOf(null).key;
  String _length = 'medium';
  double _temp = AiService.defaultTemperature;
  List<String> _constraints = [];

  /// 「联网搜索」开关（默认开，老库没这一列时也按开处理）
  bool _webSearch = true;
  bool _loaded = false;

  final _inputCtrl = TextEditingController();

  static const _presets = kAiCoachPresetConstraints;

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
      // 没存过 / 存了未知 key 都回落到默认风格（豆包感）
      _style = AiCoachOptions.styleOf(s?.aiStyle).key;
      _length = s?.aiReplyLength ?? AiCoachOptions.lengthOf(null).key;
      _temp =
          (s?.aiTemperature ?? AiService.defaultTemperature).clamp(0.3, 1.0);
      _constraints = AiCoachOptions.decodeConstraints(s?.aiConstraints);
      _webSearch = s?.aiWebSearchEnabled ?? true;
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
    setState(
        () => _constraints = _constraints.where((e) => e != text).toList());
    _save();
  }

  /// 切换「联网搜索」：立刻存库 + 刷新设置，下一条消息就按新开关走
  Future<void> _toggleWebSearch(bool value) async {
    setState(() => _webSearch = value);
    await ref.read(userSettingsRepoProvider).save(aiWebSearchEnabled: value);
    ref.invalidate(userSettingsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(value ? '已开启联网搜索' : '已关闭联网搜索'),
          duration: const Duration(seconds: 2),
        ),
      );
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
                AiModelConfigCard(webSearch: _webSearch),
                const SizedBox(height: 20),
                const AiCoachSectionTitle('教练风格'),
                const SizedBox(height: 8),
                for (final s in AiCoachOptions.styles)
                  AiCoachStyleCard(
                    style: s,
                    selected: _style == s.key,
                    onTap: () {
                      setState(() => _style = s.key);
                      _save();
                    },
                  ),
                const SizedBox(height: 20),
                const AiCoachSectionTitle('回复长度'),
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
                const AiCoachSectionTitle('自由度'),
                const SizedBox(height: 2),
                Text(
                  _temp <= 0.5
                      ? '偏稳定：严格守规矩，措辞更保守'
                      : (_temp >= 0.85 ? '偏灵活：更有梗、更即兴，话也会多一点' : '均衡：规矩和发挥各占一半'),
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
                const AiCoachSectionTitle('联网搜索'),
                AiWebSearchTile(
                  value: _webSearch,
                  onChanged: _toggleWebSearch,
                ),
                const SizedBox(height: 16),
                const AiCoachSectionTitle('自定义约束'),
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
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textTertiary)),
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
                const SizedBox(height: 18),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: SettingsTile(
                    icon: Icons.badge_outlined,
                    color: AppColors.analysis,
                    title: '人设文案',
                    subtitle: '查看并自定义嘎教练的人设（高级）',
                    onTap: () => context.push('/ai/persona'),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  '设定改完立刻保存，下一条消息生效。想让语气更准，建议先清空聊天记录再试。',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiary, height: 1.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  // 与服务层共用同一句话，改价只改一处
                  WebToolsService.priceNote,
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textTertiary, height: 1.5),
                ),
              ],
            ),
    );
  }
}
