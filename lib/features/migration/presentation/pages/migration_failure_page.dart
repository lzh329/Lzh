import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fittrack/core/database/database_health.dart';
import 'package:fittrack/core/database/migration_failure_marker.dart';
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

  int get _attempts => widget.marker.attemptCount;

  bool get _escalated =>
      DatabaseRecoveryService.shouldEscalateToBackup(_attempts);

  /// 库版本比 App 新：既不能当僵尸删掉，也不能让用户点「恢复」把新数据盖掉。
  bool get _newerData => widget.verdict == MarkerVerdict.newerData;

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

  /// 把当前库复制出去（**不删原文件**），用于排查。
  Future<void> _exportBrokenDatabase() async {
    setState(() => _busy = true);
    try {
      final path = await DatabaseRecoveryService.exportBrokenDatabase();
      await Share.shareXFiles([XFile(path)], text: '减肥嘎 数据库排查文件');
      _toast('已导出：$path');
    } catch (_) {
      _toast('导出失败，可以稍后再试');
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
                    ? '这个数据是更新版本的 App 创建的，当前版本打不开它。你的记录都还在，更新 App 就能继续用。'
                    : '数据升级没完成，你的记录都还在。新功能暂时用不了，可以再试一次。',
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
    final backupAsPrimary = _escalated || _newerData;

    final restoreButton = FilledButton.icon(
      onPressed: _busy ? null : _restoreFromBackup,
      icon: const Icon(Icons.restore_rounded),
      label: Text(
        _newerData ? '用备份恢复（会覆盖新版本数据）' : (_escalated ? '先用备份恢复，再排查' : '从备份恢复'),
      ),
    );

    final exportButton = OutlinedButton.icon(
      onPressed: _busy ? null : _exportBrokenDatabase,
      icon: const Icon(Icons.save_alt_rounded),
      label: Text(backupAsPrimary ? '还不行，先把数据存一份' : '先存一份数据'),
    );

    final retryButton = TextButton(
      onPressed: _busy ? null : _restart,
      child: Text(_busy ? '处理中…' : '再试一次'),
    );

    if (backupAsPrimary) {
      return [
        exportButton,
        const SizedBox(height: 12),
        restoreButton,
        const SizedBox(height: 8),
        retryButton,
      ];
    }
    return [
      restoreButton,
      const SizedBox(height: 12),
      exportButton,
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
