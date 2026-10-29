import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'package:fittrack/core/theme/app_colors.dart';

const _green = AppColors.primary;
const _amber = AppColors.warning;
const _blue = AppColors.info;
const _purple = AppColors.analysis;

/// 身体信息页 —— v2 视觉统一（分组卡 + 彩色图标 + 大数字计算卡）
class ProfileBodyInfo extends ConsumerStatefulWidget {
  const ProfileBodyInfo({super.key});

  @override
  ConsumerState<ProfileBodyInfo> createState() => _ProfileBodyInfoState();
}

class _ProfileBodyInfoState extends ConsumerState<ProfileBodyInfo> {
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
    final settings = ref.watch(userSettingsProvider).valueOrNull;

    final bmr = settings?.bmr();
    final tdee = settings?.tdee();
    final hasCalc = bmr != null && tdee != null;

    // 纯搬运：Scaffold/AppBar 归新页；列表底部本来就有「保存」按钮，功能不丢。
    // 嵌在个人档案页（SingleChildScrollView）里 → 必须 shrinkWrap + 关自滚，
    // 否则会抛 "Vertical viewport was given unbounded height"。
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _group(
          theme,
          icon: Icons.person_outline,
          color: _green,
          title: '身体数据',
          children: [
            TextField(
              controller: _heightCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '身高',
                suffixText: 'cm',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _targetCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '目标体重',
                suffixText: '斤',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _group(
          theme,
          icon: Icons.wc,
          color: _blue,
          title: '性别',
          children: [
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
        const SizedBox(height: 12),
        _group(
          theme,
          icon: Icons.cake_outlined,
          color: _amber,
          title: '出生日期',
          children: [
            InkWell(
              onTap: _pickBirthDate,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      _birthDate != null
                          ? DateFormat('yyyy年M月d日').format(_birthDate!)
                          : '点击选择',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (settings?.age != null)
                      Text(
                        '  ·  ${settings!.age} 岁',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _group(
          theme,
          icon: Icons.directions_run,
          color: _purple,
          title: '活动等级',
          children: [
            RadioGroup<String>(
              groupValue: _activityLevel,
              onChanged: (v) => setState(() => _activityLevel = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: UserSettingsEntity.activityLevelLabels.entries
                    .map((e) => ListTile(
                          title:
                              Text(e.value, style: theme.textTheme.bodyMedium),
                          leading: Radio<String>(value: e.key),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          onTap: () => setState(() => _activityLevel = e.key),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── 代谢与消耗 ──
        if (hasCalc)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _green.withAlpha(32),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.bolt, size: 16, color: _green),
                      ),
                      const SizedBox(width: 10),
                      Text('代谢与消耗', style: theme.textTheme.titleSmall),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _CalcStat(
                          label: '基础代谢',
                          value: '${bmr.toInt()}',
                          unit: 'kcal/天',
                          color: AppColors.primaryText,
                        ),
                      ),
                      Expanded(
                        child: _CalcStat(
                          label: '每日消耗',
                          value: '${tdee.toInt()}',
                          unit: 'kcal/天',
                          color: _amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: AppColors.border),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '减脂建议 ${(tdee * 0.8).toInt()} kcal/天',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.primaryText),
                      ),
                      const Spacer(),
                      Text(
                        '增肌建议 ${(tdee * 1.1).toInt()} kcal/天',
                        style: const TextStyle(fontSize: 11, color: _amber),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  '填写身高、出生日期、性别后\n可计算基础代谢率和每日消耗',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: AppColors.onPrimary,
            ),
            onPressed: _save,
            child: const Text('保存',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _group(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Text(title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CalcStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _CalcStat({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(width: 4),
            Text(
              unit,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
