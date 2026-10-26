import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/features/settings/presentation/settings_actions.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/auto_backup_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 数据管理页 —— 导出 / 自动备份 / 备份恢复
///
/// 低频功能从「我的」主页面收进这里，主页面保持轻量。
class DataManagementPage extends ConsumerStatefulWidget {
  const DataManagementPage({super.key});

  @override
  ConsumerState<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends ConsumerState<DataManagementPage> {
  DateTime? _lastBackupAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshLastBackup();
  }

  Future<void> _refreshLastBackup() async {
    final t = await AutoBackupService.lastBackupAt();
    if (mounted) setState(() => _lastBackupAt = t);
  }

  Future<void> _toggleAutoBackup(bool v) async {
    await ref.read(userSettingsRepoProvider).save(autoBackupEnabled: v);
    ref.invalidate(userSettingsProvider);
  }

  Future<void> _backupNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AutoBackupService.backupNow();
      await _refreshLastBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份完成（保留最近 4 份）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _lastBackupLabel {
    final t = _lastBackupAt;
    if (t == null) return '还没有备份';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚备份过';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前备份';
    if (diff.inDays < 1) return '${diff.inHours} 小时前备份';
    return '${DateFormat('MM-dd HH:mm').format(t)} 备份';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    final autoEnabled = settings?.autoBackupEnabled ?? true;

    return Scaffold(
      appBar: AppBar(title: const Text('数据管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // ── 导出 ──
          SettingsSection(
            title: '导出',
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
            ],
          ),
          const SizedBox(height: 18),

          // ── 自动备份 ──
          SettingsSection(
            title: '自动备份',
            children: [
              SettingsTile(
                icon: Icons.autorenew_outlined,
                color: AppColors.primary,
                title: '每周自动备份',
                subtitle: '启动时检查，超过 7 天自动备份到本机',
                trailing:
                    Switch(value: autoEnabled, onChanged: _toggleAutoBackup),
              ),
              SettingsTile(
                icon: Icons.history_outlined,
                color: _grey,
                title: _lastBackupLabel,
                subtitle: '保留最近 4 份 · 可在恢复数据库中使用',
                onTap: _busy ? null : _backupNow,
                trailing: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload_outlined,
                        size: 18, color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // ── 备份 / 恢复 ──
          SettingsSection(
            title: '备份与恢复',
            children: [
              SettingsTile(
                icon: Icons.backup_outlined,
                color: _grey,
                title: '导出数据库',
                subtitle: '生成备份文件并分享（网盘/电脑保存）',
                onTap: () => backupDatabase(context),
              ),
              SettingsTile(
                icon: Icons.restore,
                color: _grey,
                title: '恢复数据库',
                subtitle: '从最近一次备份恢复（需重启）',
                onTap: () => restoreDatabase(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _grey = AppColors.textTertiary;
}
