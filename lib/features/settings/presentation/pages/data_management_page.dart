import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/features/settings/presentation/settings_actions.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

/// 数据管理页 —— 导出 / 备份 / 恢复
///
/// 低频功能从「我的」主页面收进这里，主页面保持轻量。
class DataManagementPage extends ConsumerWidget {
  const DataManagementPage({super.key});

  static const _grey = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

          // ── 备份 ──
          SettingsSection(
            title: '备份',
            children: [
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
        ],
      ),
    );
  }
}
