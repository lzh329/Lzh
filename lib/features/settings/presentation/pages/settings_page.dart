import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/settings/presentation/settings_actions.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_header_card.dart';
import 'package:fittrack/features/settings/presentation/widgets/sick_day_toggle_tile.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// "我的"（设置）页 —— v2 重做
///
/// 结构：个人资料卡 → 目标与记录 → 提醒与语音 → 外观 → 隐私 → 数据 → 关于
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _green = AppColors.primary;
  static const _blue = AppColors.info;
  static const _purple = AppColors.analysis;
  static const _orange = AppColors.warning;
  static const _grey = AppColors.textTertiary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
            onTap: () => context.push('/settings/profile'),
          ),
          const SizedBox(height: 18),

          // ── 我的档案 ──
          SettingsSection(
            title: '我的档案',
            children: [
              // 原来的「目标管理」「身体信息」两个入口已合并成一页：
              // 它们在用户心里是同一件事，分两个入口只会来回找
              SettingsTile(
                icon: Icons.badge_outlined,
                color: _green,
                title: '个人档案',
                subtitle: _bodyInfoSubtitle(ref),
                onTap: () => context.push('/settings/profile'),
              ),
              SettingsTile(
                icon: Icons.fitness_center,
                color: _blue,
                title: '动作库',
                subtitle: '查看、添加、编辑训练动作',
                onTap: () => context.push('/settings/exercises'),
              ),
              SettingsTile(
                icon: Icons.photo_library,
                color: _blue,
                title: '身体相册',
                subtitle: '查看和管理身体照片',
                onTap: () => context.push('/body/album'),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 偏好设置 ──
          SettingsSection(
            title: '偏好设置',
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
              // 「今天不舒服」手动开关 —— 不依赖任何 AI 配置，没配 Key 也能用。
              // 放在提醒下面：它写的第一件事就是"今天提醒暂停"。
              const SickDayToggleTile(),
              SettingsTile(
                icon: Icons.record_voice_over,
                color: _orange,
                title: '语音教练',
                subtitle: voiceEnabled ? '已启用 · 语速与音色可调' : '关闭',
                onTap: () => context.push('/settings/voice'),
              ),
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

          // ── 数据与关于 ──
          SettingsSection(
            title: '数据与关于',
            children: [
              SettingsTile(
                icon: Icons.storage_outlined,
                color: _grey,
                title: '数据管理',
                subtitle: '导出训练 / 身体数据 · 备份与恢复',
                onTap: () => context.push('/settings/data'),
              ),
              const SettingsTile(
                icon: Icons.info_outline,
                color: _grey,
                title: '关于减肥嘎',
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
                color: AppColors.textTertiary,
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
