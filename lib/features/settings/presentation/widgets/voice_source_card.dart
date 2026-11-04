import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/cloud_voice_config.dart';
import 'package:fittrack/core/services/cloud_voice_player.dart';
import 'package:fittrack/core/services/edge_tts_service.dart';
import 'package:fittrack/core/services/minimax_tts_service.dart';
import 'package:fittrack/core/services/voice_presets.dart';
import 'package:fittrack/core/services/workout_coach.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/presentation/widgets/voice_preset_tile.dart';

/// 「音色来源」卡片：系统 / Edge（免费）/ MiniMax（付费）三选一 + 5 个预设。
///
/// 三个刻意的产品选择：
/// 1. **默认 Edge**：不填任何 Key 也能听到接近商用的人声；它失效会自动回落系统 TTS，
///    所以"默认选它"不会把用户坑哑；
/// 2. **一个预设两套音色**（`edgeVoiceId` / `voiceId`），换通道不用重选预设；
/// 3. **试听直连对应服务、不回落**：回落会让用户以为云端已生效。
///    只有"系统"模式下试听才走系统 TTS。
class VoiceSourceCard extends ConsumerStatefulWidget {
  const VoiceSourceCard({super.key});

  @override
  ConsumerState<VoiceSourceCard> createState() => _VoiceSourceCardState();
}

class _VoiceSourceCardState extends ConsumerState<VoiceSourceCard> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _baseCtrl;

  String? _previewing;
  bool _advancedOpen = false;

  static const _sample = '你好，我是你的训练教练。准备开始第一组。';

  CloudVoiceConfig get _config => CloudVoiceConfig.fromJsonString(
      ref.watch(userSettingsProvider).valueOrNull?.ttsConfig);

  @override
  void initState() {
    super.initState();
    final c = CloudVoiceConfig.fromJsonString(
        ref.read(userSettingsProvider).valueOrNull?.ttsConfig);
    _keyCtrl = TextEditingController(text: c.apiKey ?? '');
    _groupCtrl = TextEditingController(text: c.groupId ?? '');
    _baseCtrl = TextEditingController(text: c.baseUrl ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _groupCtrl.dispose();
    _baseCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(CloudVoiceConfig next) async {
    await ref.read(userSettingsRepoProvider).save(ttsConfig: next.toJsonString());
    ref.invalidate(userSettingsProvider);
  }

  /// 用输入框现值 + 覆盖项构造（避免"改了 Key 但预设还是旧的"）
  CloudVoiceConfig _withInputs(CloudVoiceConfig base,
          {VoiceSource? source, String? presetId}) =>
      base.copyWith(
        source: source,
        presetId: presetId,
        apiKey: _keyCtrl.text.trim(),
        groupId: _groupCtrl.text.trim(),
        baseUrl: _baseCtrl.text.trim(),
      );

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// 试听：系统模式走系统 TTS；Edge/MiniMax 直连对应服务（失败提示，不回落）
  Future<void> _preview(VoicePreset preset) async {
    final source = _config.source;
    if (source == VoiceSource.system) {
      final coach = WorkoutCoach();
      final s = ref.read(userSettingsProvider).valueOrNull;
      coach.applySettings(
        rate: s?.speechRate ?? 0.45,
        pitch: s?.speechPitch ?? 1.0,
        voiceName: s?.ttsVoice,
      );
      coach.disableCloud();
      coach.enabled = true;
      await coach.speak(_sample);
      return;
    }

    setState(() => _previewing = preset.id);
    try {
      final bytes = await _synthesizeFor(source, preset);
      await CloudVoicePlayer.playOnce(bytes);
    } on MinimaxTtsException catch (e) {
      _toast(e.message);
    } on EdgeTtsException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('试听失败：$e');
    } finally {
      if (mounted) setState(() => _previewing = null);
    }
  }

  Future<Uint8List> _synthesizeFor(VoiceSource source, VoicePreset preset) {
    if (source == VoiceSource.edge) {
      return EdgeTtsService.synthesize(
        text: _sample,
        voiceId: preset.edgeVoiceId,
        speed: preset.speed,
        pitch: preset.pitch,
      );
    }
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) throw const MinimaxTtsException('还没填 MiniMax API Key');
    return MinimaxTtsService.synthesize(
      text: _sample,
      apiKey: key,
      groupId: _groupCtrl.text.trim(),
      voiceId: preset.voiceId,
      speed: preset.speed,
      pitch: preset.pitch,
      baseUrl: _baseCtrl.text.trim().isEmpty
          ? MinimaxTtsService.defaultBaseUrl
          : _baseCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config;
    final selected = config.preset;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.graphic_eq,
                    size: 18, color: AppColors.primaryText),
                const SizedBox(width: 6),
                Text('音色来源', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            _sourceTile(
              value: VoiceSource.system,
              title: '系统音色',
              subtitle: '零配置、离线可用，音质看手机',
              current: config.source,
              onPick: (v) => _save(_withInputs(config, source: v)),
            ),
            _sourceTile(
              value: VoiceSource.edge,
              title: 'Edge（免费）',
              subtitle: '无需 Key，接近商用的人声；非官方接口，失效会自动回落系统音色',
              current: config.source,
              onPick: (v) => _save(_withInputs(config, source: v)),
              badge: '推荐',
            ),
            _sourceTile(
              value: VoiceSource.minimax,
              title: 'MiniMax（付费）',
              subtitle: '音质最好，需要填 API Key',
              current: config.source,
              onPick: (v) => _save(_withInputs(config, source: v)),
            ),
            if (config.isMinimax) ..._minimaxFields(config),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text('选一个听起来顺耳的（点卡片即切换）',
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                ),
                if (config.isMinimax && _keyCtrl.text.trim().isEmpty)
                  const Text('未配置 Key 时用 Edge/系统',
                      style: TextStyle(fontSize: 10.5, color: AppColors.danger)),
              ],
            ),
            const SizedBox(height: 8),
            for (final p in VoicePresets.all)
              VoicePresetTile(
                preset: p,
                selected: p.id == selected.id,
                previewing: _previewing == p.id,
                onTap: () => _save(_withInputs(config, presetId: p.id)),
                onPreview: () => _preview(p),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _minimaxFields(CloudVoiceConfig config) => [
        _field(
          label: 'API Key',
          controller: _keyCtrl,
          hint: 'MiniMax 控制台里的 API Key',
          obscure: true,
          onSaved: () => _save(_withInputs(config)),
        ),
        _field(
          label: 'GroupId（可选）',
          controller: _groupCtrl,
          hint: '国内站多数接口需要',
          onSaved: () => _save(_withInputs(config)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _advancedOpen = !_advancedOpen),
            child: Text(_advancedOpen ? '收起高级设置' : '高级设置（国际站 baseUrl）',
                style: const TextStyle(fontSize: 11)),
          ),
        ),
        if (_advancedOpen)
          _field(
            label: 'BaseUrl',
            controller: _baseCtrl,
            hint: '默认 ${MinimaxTtsService.defaultBaseUrl}；国际站 api.minimax.io',
            onSaved: () => _save(_withInputs(config)),
          ),
      ];

  Widget _sourceTile({
    required VoiceSource value,
    required String title,
    required String subtitle,
    required VoiceSource current,
    required ValueChanged<VoiceSource> onPick,
    String? badge,
  }) {
    final selected = current == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onPick(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.primary : AppColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(24),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(badge,
                              style: const TextStyle(
                                  fontSize: 9.5, color: AppColors.primaryText)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 10.5,
                          height: 1.35,
                          color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onSaved,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Focus(
        // 失焦才写库：每敲一个字都写一次 SQLite 没必要
        onFocusChange: (hasFocus) {
          if (!hasFocus) onSaved();
        },
        child: TextField(
          controller: controller,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onSubmitted: (_) => onSaved(),
          onChanged: (_) => setState(() {}), // 让"未配置 Key"提示即时更新
        ),
      ),
    );
  }
}
