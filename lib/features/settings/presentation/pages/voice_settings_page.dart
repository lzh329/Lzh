import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/workout_coach.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 语音教练设置页
///
/// 从原设置页的语音卡片迁移而来，独立成页以便主设置页更清爽。
class VoiceSettingsPage extends ConsumerStatefulWidget {
  const VoiceSettingsPage({super.key});

  @override
  ConsumerState<VoiceSettingsPage> createState() => _VoiceSettingsPageState();
}

class _VoiceSettingsPageState extends ConsumerState<VoiceSettingsPage> {
  List<Map<String, String>> _voices = [];
  bool _voicesLoaded = false;

  static const _green = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final voices = await WorkoutCoach().getVoices();
    if (mounted) {
      setState(() {
        _voices = voices;
        _voicesLoaded = true;
      });
    }
  }

  Future<void> _preview() async {
    final coach = WorkoutCoach();
    final s = ref.read(userSettingsProvider).valueOrNull;
    coach.applySettings(
      rate: s?.speechRate ?? 0.45,
      pitch: s?.speechPitch ?? 1.0,
      voiceName: s?.ttsVoice,
    );
    coach.enabled = true;
    await coach.speak('你好，这是试听效果');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = ref.watch(userSettingsProvider).valueOrNull;
    final rate = s?.speechRate ?? 0.45;
    final pitch = s?.speechPitch ?? 1.0;
    final voice = s?.ttsVoice ?? '';
    final enabled = rate > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('语音教练'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              secondary: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _green.withAlpha(32),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.record_voice_over,
                    size: 18, color: _green),
              ),
              title: const Text('启用语音播报'),
              subtitle: const Text('训练时朗读动作名称与倒计时'),
              value: enabled,
              onChanged: (v) async {
                await ref
                    .read(userSettingsRepoProvider)
                    .save(speechRate: v ? 0.45 : 0);
                ref.invalidate(userSettingsProvider);
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('音色与节奏', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 16),
                  _sliderRow(
                    icon: Icons.speed,
                    label: '语速',
                    value: rate.clamp(0.2, 1.0),
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    onEnd: (v) async {
                      await ref
                          .read(userSettingsRepoProvider)
                          .save(speechRate: v);
                      ref.invalidate(userSettingsProvider);
                    },
                  ),
                  _sliderRow(
                    icon: Icons.graphic_eq,
                    label: '音调',
                    value: pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    onEnd: (v) async {
                      await ref
                          .read(userSettingsRepoProvider)
                          .save(speechPitch: v);
                      ref.invalidate(userSettingsProvider);
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.voice_chat, size: 18),
                      const SizedBox(width: 8),
                      Text('音色', style: theme.textTheme.bodySmall),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _voicesLoaded
                            ? DropdownButton<String>(
                                value: voice.isEmpty
                                    ? (_voices.isNotEmpty
                                        ? _voices.first['name']
                                        : '')
                                    : voice,
                                isExpanded: true,
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('系统默认',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                  ..._voices.map((v) => DropdownMenuItem(
                                        value: v['name'],
                                        child: Text(
                                          v['name'] ?? v['locale'] ?? '',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      )),
                                ],
                                onChanged: (v) async {
                                  if (v == null) return;
                                  await ref
                                      .read(userSettingsRepoProvider)
                                      .save(ttsVoice: v.isEmpty ? null : v);
                                  ref.invalidate(userSettingsProvider);
                                },
                              )
                            : const Text('加载中...',
                                style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: AppColors.onPrimary,
              ),
              onPressed: _preview,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('试听当前设置'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onEnd,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodySmall),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(2),
            onChanged: (_) {},
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toStringAsFixed(2),
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
