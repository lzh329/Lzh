import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fittrack/core/database/database_health.dart';
import 'package:fittrack/core/database/migration_failure_marker.dart';
import 'package:fittrack/core/services/backup_service.dart';
import 'package:fittrack/core/services/restore_service.dart';
import 'package:fittrack/core/services/database_recovery_service.dart';
import 'package:fittrack/core/theme/app_theme.dart';

/// 数据库打不开 / 迁移未完成时的降级 App。
///
/// 设计原则只有一条：**用户至少能看到一句话，并且永远有一条出路**。
///
/// 所以这里刻意**不**是 ConsumerWidget、不 import providers、不碰任何
/// Repository —— 数据库此刻就是打不开的那个东西，watch 任何 DB provider 都会
/// 二次抛错。整页只做文件 IO（备份 / 复制 / 删除 WAL），这条路在降级态一定可用。
class DatabaseFailureApp extends StatelessWidget {
  final MigrationFailureMarker marker;

  /// 库版本判定结果（用来区分僵尸 marker / 真失败 / 版本比 App 新）
  final MarkerVerdict verdict;

  const DatabaseFailureApp({
    super.key,
    required this.marker,
    this.verdict = MarkerVerdict.genuine,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '减肥嘎',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: DatabaseFailurePage(marker: marker, verdict: verdict),
    );
  }
}

class DatabaseFailurePage extends StatefulWidget {
  final MigrationFailureMarker marker;
  final MarkerVerdict verdict;

  const DatabaseFailurePage({
    super.key,
    required this.marker,
    this.verdict = MarkerVerdict.genuine,
  });

  @override
  State<DatabaseFailurePage> createState() => _DatabaseFailurePageState();
}

class _DatabaseFailurePageState extends State<DatabaseFailurePage> {
  bool _busy = false;

  /// 「回到恢复前的数据」的来源。null = 没有可退回的点 → 按钮不渲染
  /// （不给一个点了没反应的入口）。
  String? _preRestorePath;

  @override
  void initState() {
    super.initState();
    _loadPreRestore();
  }

  Future<void> _loadPreRestore() async {
    try {
      _preRestorePath = await RestoreService.latestPreRestore();
    } catch (_) {
      _preRestorePath = null;
    }
    if (mounted) setState(() {});
  }

  int get _attempts => widget.marker.attemptCount;

  bool get _escalated =>
      DatabaseRecoveryService.shouldEscalateToBackup(_attempts);

  /// 库版本比 App 新：既不能当僵尸删掉，也不能让用户点「恢复」把新数据盖掉。
  bool get _newerData => widget.verdict == MarkerVerdict.newerData;

  /// ④ 档：文件头读不出，或压根没发生过升级尝试（attemptCount == 0）。
  ///
  /// 这一档**不能说**「你的记录都还在」—— 读不出 `user_version` 时我们无法
  /// 验证记录还在，那是没有依据的安慰，比不说更糟。② 才可以说，因为版本号读得
  /// 出来说明库至少结构可读。
  bool get _conservative =>
      widget.verdict == MarkerVerdict.unreadable || _attempts == 0;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// 从备份恢复：**先强制备份当前库（失败即中止）** → 覆盖 → 清 WAL → 重启。
  Future<void> _restoreFromBackup() async {
    setState(() => _busy = true);
    try {
      final backupPath = await DatabaseRecoveryService.findRestorableBackup();
      if (backupPath == null) {
        _toast('没找到可用的备份文件');
        return;
      }
      final safetyCopy = await DatabaseRecoveryService.restoreFromBackup(
          backupPath: backupPath);
      final name = safetyCopy.split(Platform.pathSeparator).last;
      _toast('恢复完成，正在重启（旧数据已另存为 $name）');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _restart();
    } catch (_) {
      // 恢复流程的任何异常都不许冒泡成白屏
      _toast('恢复失败，你的原数据没有被改动');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 先存一份数据 = **完整备份包**（zip：整库快照 + photos/ + manifest）。
  ///
  /// 不用 CSV、也不只 copy `.sqlite`：照片在 `documents/photos/` 是独立文件，
  /// 只给 db 会让用户在最重要的时候少一半数据 —— 而我们的承诺是「记录都还在」。
  ///
  /// 降级态调 `createArchive(allowOpenDatabase: ...)`：
  /// - 库结构还能读 → `VACUUM INTO` 出干净快照；
  /// - 打不开 → 整组 raw copy（db + 存在才带的 -wal/-shm/-journal）。
  /// 无论哪条都要做，所以先试快照、失败自动降级，不让用户自己判断。
  Future<void> _exportArchive() async {
    setState(() => _busy = true);
    try {
      BackupArchive? archive;
      try {
        archive = await BackupService.createArchive();
      } catch (_) {
        // 连 VACUUM 都起不来时，退回纯文件搬运（不打开库）
        archive = await BackupService.createArchive(allowOpenDatabase: false);
      }
      await Share.shareXFiles(
        [XFile(archive.path)],
        text: '减肥嘎 完整备份（数据库 + 照片）',
      );
      final how = archive.dbSource == 'snapshot' ? '已做一致性快照' : '原样打包';
      _toast('已存好：${archive.photoCount} 张照片（$how）');
    } catch (_) {
      _toast('存数据失败，可以稍后再试。先别卸载 App。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 回到恢复前的数据 = 再走一次完整校验链的恢复。
  ///
  /// `pre-restore` 文件没人保证完整（磁盘错误 / 写到一半被杀），所以绝不能用
  /// 一条"直接覆盖"的快路径 —— 那等于用可能坏掉的数据二次毁现场，
  /// 而用户此刻已经没有第三份了。
  Future<void> _rollbackToPreRestore() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('回到恢复前的数据'),
        content: const Text(
          '会用恢复前的那份数据替换现在的内容。刚才恢复的数据会被覆盖，但备份包还在。\n'
          '被覆盖的那份数据不会留副本。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认退回'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await RestoreService.restoreFromPreRestore(
        preRestorePath: _preRestorePath!,
      );
      // 退回成功后必须显式清 marker —— 不清的话下次启动又进降级页。
      // 僵尸 marker 自愈能兜住，但不能让第二条路径去修第一条路径的遗漏。
      await MigrationFailureMarker.clear();
      _toast('退回完成。请把 App 关掉再打开一次，让数据重新加载。');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      _restart();
    } catch (e) {
      final reason = e is RestoreAborted ? e.reason : null;
      _toast(reason ?? '退回没成功，那份恢复前的数据打不开了。你现在的记录没被动过，先把数据存一份。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: widget.marker.diagnostics));
    _toast('诊断信息已复制');
  }

  /// 「再试一次」= 重启进程重新走一遍启动流程。
  ///
  /// 不用 `exit(0)`：Android 上直接退进程可能被系统当成崩溃上报，
  /// `SystemNavigator.pop()` 是 Flutter 里最稳的「退出到桌面」方式。
  void _restart() => SystemNavigator.pop();

  @override
  Widget build(BuildContext context) {
    final marker = widget.marker;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _newerData
                    ? Icons.system_update_alt_rounded
                    : Icons.storage_rounded,
                size: 52,
              ),
              const SizedBox(height: 20),
              // ── 产品定稿文案：第一句必须出现「记录都还在」 ──
              Text(
                _newerData
                    ? '这份数据是更新版本的减肥嘎存的，当前版本读不了。'
                        '装上最新的安装包再打开即可，数据不会丢。'
                    : (_conservative
                        ? '数据打不开，先别卸载。可以再试一次，或先把现在能拿到的数据存一份。'
                        : '数据升级没完成，你的记录都还在。新功能暂时用不了，可以再试一次。'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '升级与恢复都在本地进行，不会上传任何记录。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 28),
              ..._buildActions(),
              const SizedBox(height: 28),
              _buildDiagnostics(marker),
            ],
          ),
        ),
      ),
    );
  }

  /// 按钮层级：
  /// - 1~3 次失败 →「从备份恢复」为主、「先存一份数据」为次；
  /// - 第 3 次之后 →「先存一份数据」提到主位，文案改「还不行，先把数据存一份」，
  ///   「再试一次」降为灰底文字按钮但**不禁用**。
  ///
  /// 理由：连点 3 次都失败的人最容易做错决定（卸载重装）。那一刻我们要把主按钮
  /// 换成「先备份」，而不是催他点第 4 次。但不禁用「再试一次」—— 空间不足这类
  /// 偶发问题清完就好了，禁用等于判死刑。
  List<Widget> _buildActions() {
    // ③ 数据比 App 新：主按钮只能是「先存一份数据」（没有商店可跳，
    //   重试也永远不会成功，所以这一档**不出现「再试一次」**）
    // ④ 保守档：主按钮是「再试一次」（唯一有意义的动作）
    // ② 真失败：1~3 次「从备份恢复」为主，第 3 次之后「先存一份数据」上位
    final backupAsPrimary = _newerData || (!_conservative && _escalated);

    final restoreButton = FilledButton.icon(
      onPressed: _busy ? null : _restoreFromBackup,
      icon: const Icon(Icons.restore_rounded),
      label: Text(
        _newerData ? '用备份恢复（会覆盖新版本数据）' : (_escalated ? '先用备份恢复，再排查' : '从备份恢复'),
      ),
    );

    final exportButton = OutlinedButton.icon(
      onPressed: _busy ? null : _exportArchive,
      icon: const Icon(Icons.save_alt_rounded),
      label: Text(backupAsPrimary ? '还不行，先把数据存一份' : '先存一份数据'),
    );

    final retryButton = TextButton(
      onPressed: _busy ? null : _restart,
      child: Text(_busy ? '处理中…' : '再试一次'),
    );

    if (_newerData) {
      // 无「再试一次」：版本不匹配时重试永远失败，留个注定失败的按钮
      // 只会让用户反复点然后认定 App 坏了
      return [
        exportButton,
        const SizedBox(height: 12),
        restoreButton,
      ];
    }
    if (backupAsPrimary) {
      return [
        exportButton,
        const SizedBox(height: 12),
        restoreButton,
        const SizedBox(height: 8),
        retryButton,
      ];
    }
    final rollbackButton = _preRestorePath == null
        ? null
        : OutlinedButton.icon(
            onPressed: _busy ? null : _rollbackToPreRestore,
            icon: const Icon(Icons.history_rounded),
            label: const Text('回到恢复前的数据'),
          );

    if (_conservative) {
      return [
        OutlinedButton.icon(
          onPressed: _busy ? null : _restart,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(_busy ? '处理中…' : '再试一次'),
        ),
        const SizedBox(height: 12),
        exportButton,
        const SizedBox(height: 12),
        restoreButton,
        if (rollbackButton != null) ...[
          const SizedBox(height: 12),
          rollbackButton,
        ],
      ];
    }
    return [
      restoreButton,
      const SizedBox(height: 12),
      exportButton,
      if (rollbackButton != null) ...[
        const SizedBox(height: 12),
        rollbackButton,
      ],
    ];
  }

  Widget _buildDiagnostics(MigrationFailureMarker marker) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('诊断信息', style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              TextButton(onPressed: _copyDiagnostics, child: const Text('复制')),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            '卡在第几步：${marker.failingStep}\n'
            '目标版本：${marker.targetVersion}\n'
            '起始版本：${marker.fromVersion}\n'
            '尝试次数：${marker.attemptCount}\n'
            '最近失败：${_formatTime(marker.at)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            '截图这段信息发给我们，能直接定位是哪一步没完成。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  }
}
