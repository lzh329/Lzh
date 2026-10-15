import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

class BodyInfoPage extends ConsumerStatefulWidget {
  const BodyInfoPage({super.key});

  @override
  ConsumerState<BodyInfoPage> createState() => _BodyInfoPageState();
}

class _BodyInfoPageState extends ConsumerState<BodyInfoPage> {
  final _heightCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  DateTime? _birthDate;
  String? _gender;
  String? _activityLevel;

  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      final s = ref.read(userSettingsProvider).valueOrNull;
      if (s != null) {
        _heightCtrl.text = s.heightCm?.toStringAsFixed(0) ?? '';
        _targetCtrl.text = s.targetWeightKg != null
          ? (s.targetWeightKg! * 2).toStringAsFixed(1)
          : '';
        _birthDate = s.birthDate;
        _gender = s.gender;
        _activityLevel = s.activityLevel;
      }
      _loaded = true;
    }
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1990, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      locale: const Locale('zh'),
    );
    if (date != null) setState(() => _birthDate = date);
  }

  Future<void> _save() async {
    final height = double.tryParse(_heightCtrl.text);
    final targetJin = double.tryParse(_targetCtrl.text);
    await ref.read(userSettingsRepoProvider).save(
      heightCm: height,
      targetWeightKg: targetJin != null ? targetJin / 2 : null,
      birthDate: _birthDate,
      gender: _gender,
      activityLevel: _activityLevel,
    );
    ref.invalidate(userSettingsProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(userSettingsProvider);
    final settings = settingsAsync.valueOrNull;

    // 计算结果
    final bmr = settings?.bmr();
    final tdee = settings?.tdee();
    final hasCalc = bmr != null && tdee != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('身体信息'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 基本身体数据 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('身体数据', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _heightCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '身高', suffixText: 'cm', isDense: true,
                      border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _targetCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '目标体重', suffixText: '斤', isDense: true,
                      border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 性别 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('性别', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: UserSettingsEntity.genderLabels.entries
                      .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                      .toList(),
                    selected: _gender != null ? {_gender!} : {},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (v) => setState(() => _gender = v.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 出生日期 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('出生日期', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cake),
                    title: Text(
                      _birthDate != null
                        ? DateFormat('yyyy年M月d日').format(_birthDate!)
                        : '点击选择',
                    ),
                    subtitle: settings?.age != null
                      ? Text('年龄: ${settings!.age} 岁')
                      : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _pickBirthDate,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: theme.colorScheme.outline.withAlpha(60)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── 活动等级 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('活动等级', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...UserSettingsEntity.activityLevelLabels.entries.map((e) => ListTile(
                    title: Text(e.value, style: theme.textTheme.bodyMedium),
                    leading: Radio<String>(
                      value: e.key,
                      groupValue: _activityLevel,
                      onChanged: (v) => setState(() => _activityLevel = v),
                    ),
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => setState(() => _activityLevel = e.key),
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── BMR / TDEE 计算结果 ──
          if (hasCalc)
            Card(
              color: theme.colorScheme.tertiaryContainer.withAlpha(100),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _CalcItem(label: '基础代谢 BMR', value: '${bmr.toInt()}', unit: 'kcal/天', theme: theme),
                        _CalcItem(label: '每日消耗 TDEE', value: '${tdee.toInt()}', unit: 'kcal/天', theme: theme),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '减脂建议摄入: ${(tdee * 0.8).toInt()} kcal/天  |  增肌建议: ${(tdee * 1.1).toInt()} kcal/天',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
              child: const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('填写身高、出生日期、性别后\n可计算基础代谢率和每日消耗',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalcItem extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final ThemeData theme;

  const _CalcItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onTertiaryContainer,
        )),
        Text(unit, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}
