import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/settings/presentation/settings_actions.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_header_card.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

/// "我的"（设置）页 —— v2 重做
///
/// 结构：个人资料卡 → 目标与记录 → 提醒与语音 → 外观 → 隐私 → 数据 → 关于
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _green = Color(0xFF66BB6A);
  static const _amber = Color(0xFFFFA726);
  static const _blue = Color(0xFF42A5F5);
  static const _cyan = Color(0xFF26C6DA);
  static const _purple = Color(0xFFAB47BC);
  static const _orange = Color(0xFFFB8C00);
  static const _grey = Color(0xFF90A4AE);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    final latestWeight =
        ref.watch(dashboardDataProvider).valueOrNull?.latestMetric?.weightKg;

    final reminderEnabled = ref.watch(reminderEnabledProvider);
    final reminderHour = ref.watch(reminderHourProvider);
    final reminderMinute = ref.watch(reminderMinuteProvider);
    final locked = settings?.lockEnabled ?? false;
    final voiceEnabled = (settings?.speechRate ?? 0.45) > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('我的'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          // ── 个人资料 ──
          ProfileHeaderCard(
            settings: settings,
            currentWeightKg: latestWeight,
            onTap: () => context.push('/settings/body-info'),
          ),
          const SizedBox(height: 18),

          // ── 目标与记录 ──
          SettingsSection(
            title: '目标与记录',
            children: [
              SettingsTile(
                icon: Icons.flag,
                color: _amber,
                title: '目标管理',
                subtitle: '设置体重 / 训练频率目标',
                onTap: () => context.push('/goals'),
              ),
              SettingsTile(
                icon: Icons.straighten,
                color: _green,
                title: '身体信息',
                subtitle: _bodyInfoSubtitle(ref),
                onTap: () => context.push('/settings/body-info'),
              ),
              SettingsTile(
                icon: Icons.fitness_center,
                color: _blue,
                title: '动作库',
                subtitle: '查看、添加、编辑训练动作',
                onTap: () => context.push('/settings/exercises'),
              ),
              SettingsTile(
                icon: Icons.water_drop,
                color: _cyan,
                title: '饮水记录',
                subtitle: '记录每日饮水量',
                onTap: () => context.push('/water'),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 提醒与语音 ──
          SettingsSection(
            title: '提醒与语音',
            children: [
              SettingsTile(
                icon: Icons.notifications,
                color: _purple,
                title: '每日提醒',
                subtitle: reminderEnabled
                    ? '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')} 提醒（点击改时间）'
                    : '关闭',
                trailing: Switch(
                  value: reminderEnabled,
                  onChanged: (v) async {
                    ref.read(reminderEnabledProvider.notifier).state = v;
                    await ref
                        .read(userSettingsRepoProvider)
                        .save(reminderEnabled: v);
                    if (v) {
                      await scheduleReminders(ref);
                    } else {
                      await NotificationService().cancelAll();
                    }
                  },
                ),
                onTap: reminderEnabled
                    ? () => pickReminderTime(context, ref)
                    : null,
              ),
              SettingsTile(
                icon: Icons.record_voice_over,
                color: _orange,
                title: '语音教练',
                subtitle: voiceEnabled ? '已启用 · 语速与音色可调' : '关闭',
                onTap: () => context.push('/settings/voice'),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 外观 ──
          SettingsSection(
            title: '外观',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _purple.withAlpha(32),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.palette, size: 18, color: _purple),
                    ),
                    const SizedBox(width: 14),
                    Text('主题', style: theme.textTheme.bodyLarge),
                    const Spacer(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('浅色', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('深色', style: TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('跟随系统', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (v) async {
                    final mode = v.first;
                    ref.read(themeModeProvider.notifier).state = mode;
                    await ref.read(userSettingsRepoProvider).save(
                          themeMode: mode == ThemeMode.light
                              ? 'light'
                              : (mode == ThemeMode.dark ? 'dark' : 'system'),
                        );
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 隐私与安全 ──
          SettingsSection(
            title: '隐私与安全',
            children: [
              SettingsTile(
                icon: Icons.lock_outline,
                color: _grey,
                title: '隐私锁',
                subtitle: locked ? '已启用 · 进入后台需输入 PIN 码' : '关闭',
                trailing: Switch(
                  value: locked,
                  onChanged: (v) async {
                    if (v) {
                      final pin = await showPinSetupDialog(context);
                      if (pin != null) {
                        await ref.read(userSettingsRepoProvider).save(
                              pinCode: pin,
                              lockEnabled: true,
                            );
                        ref.invalidate(userSettingsProvider);
                      }
                    } else {
                      await ref
                          .read(userSettingsRepoProvider)
                          .save(lockEnabled: false);
                      ref.invalidate(userSettingsProvider);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 数据 ──
          SettingsSection(
            title: '数据',
            children: [
              SettingsTile(
                icon: Icons.file_download_outlined,
                color: _grey,
                title: '导出训练记录',
                subtitle: '导出为 CSV 文件并分享',
                onTap: () => exportWorkouts(context, ref),
              ),
              SettingsTile(
                icon: Icons.monitor_weight_outlined,
                color: _grey,
                title: '导出身体数据',
                subtitle: '体重、围度数据导出为 CSV',
                onTap: () => exportBodyMetrics(context, ref),
              ),
              SettingsTile(
                icon: Icons.backup_outlined,
                color: _grey,
                title: '备份数据库',
                subtitle: '导出完整数据库文件',
                onTap: () => backupDatabase(context),
              ),
              SettingsTile(
                icon: Icons.restore,
                color: _grey,
                title: '恢复数据库',
                subtitle: '从备份文件恢复（需重启）',
                onTap: () => restoreDatabase(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 关于 ──
          const SettingsSection(
            title: '关于',
            children: [
              SettingsTile(
                icon: Icons.info_outline,
                color: _grey,
                title: '关于简瘦',
                subtitle: 'v1.2.0 · 个人减脂助手',
                trailing: SizedBox.shrink(),
              ),
            ],
          ),

          const SizedBox(height: 28),
          Center(
            child: Text(
              '让每一次改变都被看见',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline.withAlpha(120),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _bodyInfoSubtitle(WidgetRef ref) {
    final s = ref.watch(userSettingsProvider).valueOrNull;
    if (s == null || (s.heightCm == null && s.targetWeightKg == null)) {
      return '设置身高、目标体重';
    }
    final parts = <String>[];
    if (s.heightCm != null) parts.add('${s.heightCm!.toStringAsFixed(0)} cm');
    if (s.targetWeightKg != null) {
      parts.add('目标 ${(s.targetWeightKg! * 2).toStringAsFixed(1)} 斤');
    }
    return parts.join(' · ');
  }
}
