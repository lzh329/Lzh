import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/backup_candidate_service.dart';
import 'package:fittrack/core/services/restore_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/presentation/widgets/restore_candidate_card.dart';
import 'package:fittrack/features/settings/presentation/widgets/restore_confirm_dialog.dart';

/// 打开「从哪份备份恢复」的来源选择面板。
///
/// 旧实现是"自动挑一份最新的直接覆盖"：不问用户、不校验、也永远不会用用户
/// 刚导出的那个文件 —— 这正是「导出 → 恢复后得到空库」的直接原因。
/// 面板的唯一目的是让用户**先看见**自己有几份备份、每份里有多少条记录，
/// 再决定用哪一份。
///
/// [degraded]：库**打不开**时的调用方（迁移失败页）。此时整个 App 刻意没有
/// `ProviderScope`（那层的一切都指向打不开的库），所以面板要自带一个空容器，
/// 并且一次都不读 `databaseProvider` —— 「恢复前先读一下当前行数」在降级态
/// 就是"再打开一次坏库"，等于把降级页的承诺打破。
Future<void> showDatabaseRestoreSheet(
  BuildContext context, {
  bool degraded = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => degraded
        ? const ProviderScope(child: DataRestoreSourceSheet(degraded: true))
        : const DataRestoreSourceSheet(),
  );
}

/// 候选列表（来源 → 行数摘要 → 二次确认 → 走校验链恢复）
class DataRestoreSourceSheet extends ConsumerStatefulWidget {
  /// 降级态：不碰 `databaseProvider`（见 [showDatabaseRestoreSheet]）
  final bool degraded;

  const DataRestoreSourceSheet({super.key, this.degraded = false});

  @override
  ConsumerState<DataRestoreSourceSheet> createState() =>
      _DataRestoreSourceSheetState();
}

class _DataRestoreSourceSheetState extends ConsumerState<DataRestoreSourceSheet> {
  /// null = 还在枚举
  List<BackupCandidate>? _candidates;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await BackupCandidateService.listCandidates();
      if (mounted) setState(() => _candidates = list);
    } catch (_) {
      // 枚举本身几乎不会失败（每个来源都单独 try），真失败了也按"没有候选"
      if (mounted) setState(() => _candidates = const []);
    }
  }

  /// 选一份候选 → 对比行数 → 二次确认 → 执行。
  ///
  /// `_busy` 从进入这个方法就一直保持到结束（含弹窗期间）：
  /// 恢复是"关连接 + rename 库文件"，同一时刻只允许一条流程在跑。
  Future<void> _confirmAndRestore(BackupCandidate candidate) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final current = await _currentCounts();
      if (!mounted) return;

      final preview = RestorePreview.of(candidate: candidate, current: current);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => RestoreConfirmDialog(preview: preview),
      );
      if (confirmed != true || !mounted) return;
      await _restore(candidate);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 当前库行数（读不到返回 null → 确认弹窗只说"无法对比"）
  Future<BackupCounts?> _currentCounts() async {
    // 降级态：库打不开，读行数就是"再开一次坏库"，直接按无法对比处理
    if (widget.degraded) return null;
    try {
      return await BackupCandidateService.countsOfDatabase(
        ref.read(databaseProvider),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _restore(BackupCandidate candidate) async {
    try {
      // rename 之前必须先关连接：否则旧句柄会继续往"已经被换掉的库"里写。
      // 降级态没有可用连接（本来就没打开），传 null 让服务跳过这一步。
      final close = widget.degraded ? null : _closeDatabase;
      // 两条入口共用一个骨架：zip 走完整 manifest 校验；裸 .sqlite 先做
      // 预检再打成最小 zip，同样走后续校验链与原子替换。
      final result = candidate.isArchive
          ? await RestoreService.restoreArchive(
              archivePath: candidate.path,
              closeDatabase: close,
            )
          : await RestoreService.restoreDatabaseFile(
              sourcePath: candidate.path,
              closeDatabase: close,
            );
      if (!mounted) return;
      await _showDoneDialog(result);
    } on RestoreAborted catch (e) {
      // 中止 = 原库一个字节都没动，直接把可读原因给用户
      _toast(e.reason);
    } catch (e) {
      _toast('恢复失败，你的原数据没有被改动（$e）');
    }
  }

  /// rename 之前必须先关连接：否则旧句柄会继续往"已经被换掉的库"里写。
  Future<void> _closeDatabase() async {
    try {
      await ref.read(databaseProvider).close();
    } catch (_) {
      // 库可能本来就没打开成功
    }
  }

  Future<void> _showDoneDialog(RestoreResult result) {
    final name = result.preRestorePath.split('/').last;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('数据库已恢复'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请重启应用（关掉再打开）后才会读到你恢复的数据。'),
            const SizedBox(height: 12),
            Text(
              '恢复前的旧库已另存为 $name，需要时可以再切回去。',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          // 库已被封存（本进程里的连接都是旧库），只留"退出"一条出路：
          // 多给一个"稍后"就等于让用户在一片读不到数据的页面里点来点去。
          FilledButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('退出应用'),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandle(),
            _buildHeader(),
            const Divider(height: 1, color: AppColors.border),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.borderStrong,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('选择要恢复的备份',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 2),
                const Text(
                  '按时间从新到旧。下面的行数是对这份备份的实际统计。',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final candidates = _candidates;
    if (candidates == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (candidates.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '没有找到可恢复的备份。\n'
          '先在上一页「导出数据库」存一份，或用「立即备份」做一次自动备份。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: candidates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => RestoreCandidateCard(
        candidate: candidates[i],
        onTap: _busy ? null : () => _confirmAndRestore(candidates[i]),
      ),
    );
  }
}
