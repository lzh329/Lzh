import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/workout_coach.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 通用 ──
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('动作库管理'),
                  subtitle: const Text('查看、添加、编辑训练动作'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/exercises'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.flag, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('目标管理'),
                  subtitle: const Text('设置体重 / 训练频率目标'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/goals'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.water_drop, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('饮水记录'),
                  subtitle: const Text('记录每日饮水量'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/water'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.accessibility_new, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('身体信息'),
                  subtitle: _buildBodyInfoSubtitle(ref),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/body-info'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 外观 ──
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(Icons.palette, color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: const Text('外观'),
                  subtitle: Text(_themeLabel(themeMode)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (v) async {
                      ref.read(themeModeProvider.notifier).state = v.first;
                      await ref.read(userSettingsRepoProvider).save(
                        themeMode: v.first == ThemeMode.dark ? 'dark' : 'light',
                      );
                    },
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 提醒 ──
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(Icons.notifications, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  title: const Text('每日提醒'),
                  subtitle: Text(ref.watch(reminderEnabledProvider)
                    ? '${ref.watch(reminderHourProvider).toString().padLeft(2, '0')}:${ref.watch(reminderMinuteProvider).toString().padLeft(2, '0')} 提醒'
                    : '关闭'),
                  value: ref.watch(reminderEnabledProvider),
                  onChanged: (v) async {
                    ref.read(reminderEnabledProvider.notifier).state = v;
                    await ref.read(userSettingsRepoProvider).save(reminderEnabled: v);
                    if (v) {
                      await _scheduleReminders(ref);
                    } else {
                      await NotificationService().cancelAll();
                    }
                  },
                ),
                if (ref.watch(reminderEnabledProvider))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: OutlinedButton.icon(
                      onPressed: () => _pickReminderTime(context, ref),
                      icon: const Icon(Icons.access_time, size: 16),
                      label: const Text('修改提醒时间'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 安全 ──
          Card(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final settings = ref.watch(userSettingsProvider).valueOrNull;
                    final locked = settings?.lockEnabled ?? false;
                    return SwitchListTile(
                      secondary: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.lock, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      title: const Text('隐私锁'),
                      subtitle: Text(locked ? '已启用 · 进入后台需输入 PIN 码' : '关闭'),
                      value: locked,
                      onChanged: (v) async {
                        if (v) {
                          // 设置 PIN
                          final pin = await _showPinSetupDialog(context);
                          if (pin != null) {
                            await ref.read(userSettingsRepoProvider).save(
                              pinCode: pin,
                              lockEnabled: true,
                            );
                            ref.invalidate(userSettingsProvider);
                          }
                        } else {
                          await ref.read(userSettingsRepoProvider).save(lockEnabled: false);
                          ref.invalidate(userSettingsProvider);
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 语音 ──
          _VoiceSettingsCard(),
          const SizedBox(height: 12),

          // ── 数据 ──
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.file_download, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('导出训练记录'),
                  subtitle: const Text('导出为 CSV 文件并分享'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportWorkouts(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.monitor_weight, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('导出身体数据'),
                  subtitle: const Text('体重、围度数据导出为 CSV'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _exportBodyMetrics(context, ref),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.backup, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('备份数据库'),
                  subtitle: const Text('导出完整数据库文件'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _backupDatabase(context),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.tertiaryContainer,
                    child: Icon(Icons.restore, color: theme.colorScheme.onTertiaryContainer),
                  ),
                  title: const Text('恢复数据库'),
                  subtitle: const Text('从备份文件恢复（需重启）'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _restoreDatabase(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 关于 ──
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer),
              ),
              title: const Text('关于 简瘦'),
              subtitle: const Text('v1.2.0 · 个人减肥锻炼助手'),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Icon(Icons.monitor_weight, size: 48, color: theme.colorScheme.outline.withAlpha(80)),
                const SizedBox(height: 8),
                Text('简瘦', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
                Text('让每一次改变都被看见', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline.withAlpha(150))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyInfoSubtitle(WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);
    return settings.when(
      data: (s) {
        if (s == null || (s.heightCm == null && s.targetWeightKg == null)) {
          return const Text('设置身高、目标体重');
        }
        final parts = <String>[];
        if (s.heightCm != null) parts.add('${s.heightCm!.toStringAsFixed(0)} cm');
        if (s.targetWeightKg != null) parts.add('目标 ${(s.targetWeightKg! * 2).toStringAsFixed(1)} 斤');
        return Text(parts.join(' · '));
      },
      loading: () => const Text('加载中...'),
      error: (_, __) => const Text('设置身高、目标体重'),
    );
  }

  Future<String?> _showPinSetupDialog(BuildContext context) async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? result;

    await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置 PIN 码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '输入 4 位 PIN 码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '再次输入 PIN 码',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final pin = pinCtrl.text;
              if (pin.length != 4 || pin != confirmCtrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('PIN 码不匹配或不足 4 位')));
                return;
              }
              result = pin;
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return result;
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light: return '浅色模式';
      case ThemeMode.dark: return '深色模式';
      default: return '跟随系统';
    }
  }

  Future<void> _scheduleReminders(WidgetRef ref) async {
    if (!ref.read(reminderEnabledProvider)) return;
    final hour = ref.read(reminderHourProvider);
    final minute = ref.read(reminderMinuteProvider);
    final planRepo = ref.read(planRepoProvider);
    final plans = await planRepo.getAll();
    final activePlans = plans.where((p) => p.isActive).toList();
    final ns = NotificationService();

    await ns.cancelAll();
    int id = 0;

    if (activePlans.isEmpty) {
      // 无活跃计划时安排每日通用提醒
      for (int d = 0; d < 7; d++) {
        await ns.scheduleWorkoutReminder(
          id: id++,
          planName: '每日训练',
          dayLabel: '',
          hour: hour,
          minute: minute,
          dayOfWeek: d,
        );
      }
    } else {
      for (final plan in activePlans) {
        for (final day in plan.days) {
          await ns.scheduleWorkoutReminder(
            id: id++,
            planName: plan.name,
            dayLabel: PlanDayEntity.dayLabels[day.dayOfWeek],
            hour: hour,
            minute: minute,
            dayOfWeek: day.dayOfWeek,
          );
        }
      }
    }

    // 每日称重提醒（id 从 100 开始，避免与训练提醒冲突）
    for (int d = 0; d < 7; d++) {
      await ns.scheduleDailyWeighInReminder(id: 100 + d, hour: hour, minute: minute);
    }
  }

  Future<void> _pickReminderTime(BuildContext context, WidgetRef ref) async {
    final hour = ref.read(reminderHourProvider);
    final minute = ref.read(reminderMinuteProvider);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (time != null) {
      ref.read(reminderHourProvider.notifier).state = time.hour;
      ref.read(reminderMinuteProvider.notifier).state = time.minute;
      await ref.read(userSettingsRepoProvider).save(
        reminderHour: time.hour,
        reminderMinute: time.minute,
      );
      await _scheduleReminders(ref);
    }
  }

  Future<void> _exportWorkouts(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(workoutRepoProvider);
      final workouts = await repo.getAll();
      if (workouts.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无训练记录可导出')));
        }
        return;
      }

      final buf = StringBuffer();
      buf.writeln('日期,类型,动作数,组数');
      for (final w in workouts) {
        final exerciseIds = w.sets.map((s) => s.exerciseId).toSet();
        buf.writeln('${DateFormat('yyyy-MM-dd HH:mm').format(w.date)},${w.type},${exerciseIds.length},${w.totalSets}');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fittrack_workouts_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(buf.toString());

      await Share.shareXFiles([XFile(file.path)], text: 'FitTrack 训练记录导出');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _exportBodyMetrics(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(bodyMetricRepoProvider);
      final metrics = await repo.getAll();
      if (metrics.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂无身体数据可导出')));
        }
        return;
      }

      final buf = StringBuffer();
      buf.writeln('日期,体重(斤),腰围(cm),臀围(cm),胸围(cm),备注');
      for (final m in metrics) {
        buf.writeln('${DateFormat('yyyy-MM-dd').format(m.date)},${(m.weightKg * 2).toStringAsFixed(1)},${m.waistCm ?? ''},${m.hipCm ?? ''},${m.chestCm ?? ''},${m.note ?? ''}');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fittrack_body_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(buf.toString());

      await Share.shareXFiles([XFile(file.path)], text: 'FitTrack 身体数据导出');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _backupDatabase(BuildContext context) async {
    try {
      final dbPath = await _getDbPath();
      final backupDir = Directory('/storage/emulated/0/Download');
      if (!await backupDir.exists()) {
        final dir = await getApplicationDocumentsDirectory();
        final backupFile = File('${dir.path}/fittrack_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.sqlite');
        await File(dbPath).copy(backupFile.path);
        await Share.shareXFiles([XFile(backupFile.path)], text: 'FitTrack 数据库备份');
      } else {
        final backupFile = File('${backupDir.path}/fittrack_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.sqlite');
        await File(dbPath).copy(backupFile.path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份已保存到 ${backupFile.path}')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败: $e')));
      }
    }
  }

  Future<void> _restoreDatabase(BuildContext context) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final backupFile = File('${dir.path}/fittrack_backup_latest.sqlite');

      if (!await backupFile.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未找到备份文件，请先备份或放入 fittrack_backup_latest.sqlite 到应用目录')));
        }
        return;
      }

      final dbPath = await _getDbPath();
      await backupFile.copy(dbPath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('数据库已恢复，请重启应用')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
      }
    }
  }

  Future<String> _getDbPath() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return '${dbFolder.path}/fittrack.sqlite';
  }
}

class _VoiceSettingsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_VoiceSettingsCard> createState() => _VoiceSettingsCardState();
}

class _VoiceSettingsCardState extends ConsumerState<_VoiceSettingsCard> {
  List<Map<String, String>> _voices = [];
  bool _voicesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final voices = await WorkoutCoach().getVoices();
    if (mounted) setState(() { _voices = voices; _voicesLoaded = true; });
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  radius: 18,
                  child: Icon(Icons.record_voice_over,
                    size: 18, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Text('语音设置', style: theme.textTheme.titleSmall),
                const Spacer(),
                Switch(
                  value: (s?.speechRate ?? 0.45) > 0,
                  onChanged: (v) async {
                    await ref.read(userSettingsRepoProvider).save(
                      speechRate: v ? 0.45 : 0,
                    );
                    ref.invalidate(userSettingsProvider);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 语速
            Row(
              children: [
                const Icon(Icons.speed, size: 18),
                const SizedBox(width: 8),
                Text('语速', style: theme.textTheme.bodySmall),
                Expanded(
                  child: Slider(
                    value: rate.clamp(0.2, 1.0),
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: rate.toStringAsFixed(2),
                    onChanged: (_) {},
                    onChangeEnd: (v) async {
                      await ref.read(userSettingsRepoProvider).save(speechRate: v);
                      ref.invalidate(userSettingsProvider);
                    },
                  ),
                ),
                Text(rate.toStringAsFixed(2),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),

            // 音调
            Row(
              children: [
                Transform.rotate(angle: 1.57, child: const Icon(Icons.tune, size: 18)),
                const SizedBox(width: 8),
                Text('音调', style: theme.textTheme.bodySmall),
                Expanded(
                  child: Slider(
                    value: pitch,
                    min: 0.5,
                    max: 2.0,
                    divisions: 6,
                    label: pitch.toStringAsFixed(2),
                    onChanged: (_) {},
                    onChangeEnd: (v) async {
                      await ref.read(userSettingsRepoProvider).save(speechPitch: v);
                      ref.invalidate(userSettingsProvider);
                    },
                  ),
                ),
                Text(pitch.toStringAsFixed(2),
                  style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),

            // 音色
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.voice_chat, size: 18),
                const SizedBox(width: 8),
                Text('音色', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                Expanded(
                  child: _voicesLoaded
                    ? DropdownButton<String>(
                        value: voice.isEmpty ? (_voices.isNotEmpty ? _voices.first['name'] : '') : voice,
                        isExpanded: true,
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('系统默认', style: TextStyle(fontSize: 13))),
                          ..._voices.map((v) => DropdownMenuItem(
                            value: v['name'],
                            child: Text(v['name'] ?? v['locale'] ?? '',
                              style: const TextStyle(fontSize: 13)),
                          )),
                        ],
                        onChanged: (v) async {
                          if (v == null) return;
                          await ref.read(userSettingsRepoProvider).save(ttsVoice: v.isEmpty ? null : v);
                          ref.invalidate(userSettingsProvider);
                        },
                      )
                    : const Text('加载中...', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),

            // 试听按钮
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('试听'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
