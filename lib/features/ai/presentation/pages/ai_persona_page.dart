import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_coach_settings_widgets.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 人设文案 —— 高级设置
///
/// 只做一件事：让用户看到「嘎教练现在是什么人」（当前风格默认人设），
/// 并允许他用一段自己的文案替换提示词的「角色」段。
/// 规则 / 输出格式 / 工具 / 安全边界不随人设改变（见 AiPromptBuilder）。
class AiPersonaPage extends ConsumerStatefulWidget {
  const AiPersonaPage({super.key});

  @override
  ConsumerState<AiPersonaPage> createState() => _AiPersonaPageState();
}

class _AiPersonaPageState extends ConsumerState<AiPersonaPage> {
  /// 当前风格 key（默认跟随 AiCoachOptions 的第一项）
  String _style = AiCoachOptions.styleOf(null).key;

  /// 当前回复长度 key（页面不展示，仅用于拼装提示词预览）
  String _length = AiCoachOptions.lengthOf(null).key;

  /// 已保存的自定义人设（trim 后；空串 = 未设置）
  String _savedPersona = '';

  /// 已保存的用户设置（预览提示词时复用其真实数据）
  UserSettingsEntity? _settings;

  final _ctrl = TextEditingController();
  bool _loaded = false;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await ref.read(userSettingsProvider.future);
    if (!mounted) return;
    final persona = (s?.aiPersonaCustom ?? '').trim();
    setState(() {
      _settings = s;
      _style = AiCoachOptions.styleOf(s?.aiStyle).key;
      _length = AiCoachOptions.lengthOf(s?.aiReplyLength).key;
      _savedPersona = persona;
      _ctrl.text = persona;
      _loaded = true;
    });
  }

  /// 当前风格自带的默认人设全文
  String get _defaultPersona =>
      AiCoachOptions.styleOf(_style).personaLines.join('\n');

  /// 写入数据库（空串表示恢复默认），成功后刷新用户设置
  Future<void> _persist(String persona) async {
    await ref.read(userSettingsRepoProvider).save(aiPersonaCustom: persona);
    ref.invalidate(userSettingsProvider);
    if (!mounted) return;
    setState(() => _savedPersona = persona);
  }

  Future<void> _save() async {
    await _persist(_ctrl.text.trim());
    if (!mounted) return;
    _toast('已保存，新消息生效');
  }

  Future<void> _clear() async {
    setState(() => _ctrl.clear());
    await _persist('');
    if (!mounted) return;
    _toast('已清空，恢复当前风格默认人设');
  }

  void _fillDefault() {
    setState(() {
      _ctrl.text = _defaultPersona;
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 预览用设置：只把「角色」段换成当前输入，其余沿用已保存的设置
  UserSettingsEntity _previewSettings(String persona) {
    final base = _settings;
    return UserSettingsEntity(
      id: base?.id ?? 1,
      heightCm: base?.heightCm,
      birthDate: base?.birthDate,
      gender: base?.gender,
      dailyCalorieTarget: base?.dailyCalorieTarget,
      aiStyle: _style,
      aiReplyLength: _length,
      aiConstraints: base?.aiConstraints,
      aiPersonaCustom: persona,
    );
  }

  Future<void> _previewPrompt() async {
    if (_previewing) return;
    setState(() => _previewing = true);
    final persona = _ctrl.text.trim();
    String prompt;
    try {
      // 预览要用真实数据，否则用户只会看到「暂无体重记录」的空提示词
      final trends = await ref.read(trendsDataProvider.future);
      prompt = AiPromptBuilder.build(
        trends: trends,
        settings: _previewSettings(persona),
      );
    } catch (_) {
      prompt = AiPromptBuilder.build(
        trends: const TrendsData(),
        settings: _previewSettings(persona),
      );
    }
    if (!mounted) return;
    setState(() => _previewing = false);
    await showDialog<void>(
      context: context,
      builder: (_) => AiPromptPreviewDialog(prompt: prompt),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('人设文案'), centerTitle: false),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const AiPersonaInfoCard(),
                const SizedBox(height: 18),
                const AiCoachSectionTitle('当前风格默认人设'),
                const SizedBox(height: 8),
                AiPersonaDefaultCard(
                  styleLabel: AiCoachOptions.styleOf(_style).label,
                  text: _defaultPersona,
                  onCopy: () async {
                    await Clipboard.setData(
                        ClipboardData(text: _defaultPersona));
                    if (!mounted) return;
                    _toast('默认人设已复制');
                  },
                ),
                const SizedBox(height: 18),
                const AiCoachSectionTitle('自定义人设'),
                const SizedBox(height: 6),
                Text(
                  _savedPersona.isEmpty
                      ? '当前没设置自定义人设，正在使用风格默认文案。'
                      : '当前已启用自定义人设（${_savedPersona.length} 字）。',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  minLines: 8,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 13, height: 1.6),
                  decoration: InputDecoration(
                    hintText: '留空则使用当前风格的默认人设。\n'
                        '比如：你是一位健身房里话不多但很靠谱的老哥……',
                    hintStyle: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _fillDefault,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('用当前默认填入'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textPrimary,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('清空（恢复默认）'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _previewing ? null : _previewPrompt,
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: Text(_previewing ? '正在生成…' : '预览生效的完整提示词'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '人设只决定「嘎教练是谁、怎么说话」。规则、格式、工具调用与安全边界'
                  '（不编造数据、不做医疗诊断、不承诺减重速度、劝阻极端节食）'
                  '不受人设影响，也不会被自定义文案覆盖。',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      height: 1.6),
                ),
              ],
            ),
    );
  }
}
