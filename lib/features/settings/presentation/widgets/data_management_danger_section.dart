import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 「危险操作」区块：清除所有数据。
///
/// 单独成文件的两个理由：数据管理页已经接近 300 行纪律；而这段交互（逐字确认 +
/// 先备份再删 + 清完刷新全局）是**不可撤销**的，值得被单独审阅。
class DataManagementDangerSection extends ConsumerStatefulWidget {
  const DataManagementDangerSection({super.key});

  @override
  ConsumerState<DataManagementDangerSection> createState() =>
      _DataManagementDangerSectionState();
}

class _DataManagementDangerSectionState
    extends ConsumerState<DataManagementDangerSection> {
  bool _busy = false;

  Future<void> _confirmAndWipe() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _WipeConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;

    // 先取容器再 await：等备份+删除跑完，页面可能已经不在了，
    // 那时再 ref.invalidate 会抛「已 dispose」。
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final report =
          await DataWipeService.wipeAll(db: ref.read(databaseProvider));
      _invalidateEverything(container);
      final backup = report['backup'] as String? ?? '（没生成）';
      final deleted = report['deleted'] as Map<String, int>? ?? const {};
      final total = deleted.values.fold<int>(0, (sum, c) => sum + c);
      final photos = report['photos_deleted'] as int? ?? 0;
      _toast('已清空 $total 条记录、$photos 张照片。\n'
          '备份包：$backup\n请重启应用，让页面重新加载。');
    } catch (e) {
      // 如实报错、不静默：wipeAll 是"先备份，再清空"，备份阶段失败时
      // 一条记录都没删 —— 这种情况必须说清楚，否则用户会以为数据没了。
      _toast('清除失败：$e\n'
          '如果卡在备份阶段，你的数据没有被删除；可以先去「恢复数据库」确认。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 清库**不动连接**，于是 provider 里缓存的全是"清空前的数据"。
  /// 不刷新的话用户会看到记录还在（点进去才发现是空的），以为没清干净。
  ///
  /// 这份清单与 AI 工具 `wipe_all_data` 的副作用保持一致（同一次清空，
  /// 两个入口看到的结果不能不一样）。
  void _invalidateEverything(ProviderContainer container) {
    for (final provider in <ProviderOrFamily>[
      dashboardDataProvider,
      trendsDataProvider,
      goalListProvider,
      userSettingsProvider,
      workoutTemplatesProvider,
      exerciseRepoProvider,
      aiChatRepoProvider,
      // 训练历史是页面级缓存（非 autoDispose），也必须一起失效
      workoutHistoryProvider,
    ]) {
      container.invalidate(provider);
    }
    // 内存里的提醒开关也要归位：设置行已经被删了，
    // 开关还留着"已开"只会让用户以为提醒还在生效。
    container.read(reminderEnabledProvider.notifier).state = false;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: '危险操作',
      children: [
        SettingsTile(
          icon: Icons.delete_forever_outlined,
          color: AppColors.danger,
          title: '清除所有数据',
          subtitle: '先自动备份，再清空你的记录与照片',
          onTap: _busy ? null : _confirmAndWipe,
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.danger),
        ),
      ],
    );
  }
}

/// 逐字确认弹窗。
///
/// 不做「确定 / 取消」：这个入口和「恢复数据库」挨在同一页，误触的代价是
/// 全部记录（照片文件也删）。让用户手打两个字，是这条路上最便宜的刹车。
class _WipeConfirmDialog extends StatefulWidget {
  const _WipeConfirmDialog();

  @override
  State<_WipeConfirmDialog> createState() => _WipeConfirmDialogState();
}

class _WipeConfirmDialogState extends State<_WipeConfirmDialog> {
  static const String _keyword = '清除';

  final TextEditingController _controller = TextEditingController();

  bool get _canConfirm => _controller.text == _keyword;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('清除所有数据'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '会清空你的：训练记录、体重与围度、照片、目标与计划、自定义训练模板、'
            '自定义食物、饮食与饮水记录、AI 对话、设置。清空后无法撤销。\n\n'
            '内置训练模板和内置食物库会保留 —— 清空后仍然是"刚装好就能用"的状态。\n\n'
            '清空前会先自动打一个完整备份包（含照片）。如果备份失败，一条记录都不会删。',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '输入「$_keyword」确认',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
          ),
          // 打错字/没打完 → 按钮保持禁用，不给"手快点下去"的机会
          onPressed: _canConfirm ? () => Navigator.pop(context, true) : null,
          child: const Text(_keyword),
        ),
      ],
    );
  }
}
