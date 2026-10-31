import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/migration_failure_marker.dart';
import 'package:fittrack/core/services/backup_candidate.dart';
import 'package:fittrack/features/migration/presentation/pages/migration_failure_page.dart';
import 'package:fittrack/features/settings/presentation/widgets/restore_confirm_dialog.dart';

/// 降级页（库打不开）的恢复入口。
///
/// 这是事故的原形态所在：旧实现是 `findRestorableBackup()` 盲挑 backups/ 里最新
/// 的一份直接覆盖。现在它必须和设置页走同一条路 —— **先让用户选来源**。
///
/// 两个容易回归的点，各一条：
/// 1. 源码层面：这个页面不许再出现盲选 API；
/// 2. 运行层面：降级态整个 App 没有 `ProviderScope`，面板必须能在这个环境里
///    正常打开（面板自带空容器 + 不读 databaseProvider）。
void main() {
  MigrationFailureMarker marker({int attemptCount = 1}) {
    return MigrationFailureMarker(
      fromVersion: 22,
      targetVersion: 23,
      failingStep: 'createTable:weekly_report_cache',
      attemptCount: attemptCount,
      at: DateTime(2025, 3, 4, 5, 6),
    );
  }

  test('源码守门：降级页不再自己找文件、不再 copy 覆盖', () {
    final source = File(
      'lib/features/migration/presentation/pages/migration_failure_page.dart',
    ).readAsStringSync();

    expect(source, contains('showDatabaseRestoreSheet(context, degraded: true)'),
        reason: '恢复必须走来源面板，而不是自动挑一份');
    // 断言的是**调用**而不是字符串：文档注释里提到旧实现的名字是好事
    expect(source, isNot(contains('DatabaseRecoveryService.findRestorableBackup')),
        reason: '不许再盲选备份');
    expect(source, isNot(contains('DatabaseRecoveryService.restoreFromBackup')),
        reason: '不许再 copy 覆盖');
  });

  test('源码守门：盲选 API 已从 DatabaseRecoveryService 删除', () {
    final source = File(
      'lib/core/services/database_recovery_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('findRestorableBackup() async')));
    expect(source, isNot(contains('static Future<String> restoreFromBackup')));
    // 保留的能力不能顺手删掉（迁移页与测试都在用）
    for (final kept in [
      'preRestoreFileName',
      'brokenFileName',
      'shouldEscalateToBackup',
      'journalPathsFor',
      'cleanupJournalFiles',
      'databasePath',
      'backupBeforeRestore',
      'exportBrokenDatabase',
    ]) {
      expect(source, contains(kept), reason: '$kept 必须保留');
    }
  });

  testWidgets('点「从备份恢复」能打开来源面板（降级态没有 ProviderScope，也不许崩）',
      (tester) async {
    // 故意不包 ProviderScope：这就是降级页的真实环境（bootstrap 直接返回
    // DatabaseFailureApp）。面板若去读 provider，这里会抛
    // "No ProviderScope found"，测试当场红。
    await tester.pumpWidget(DatabaseFailureApp(marker: marker()));
    await tester.pump();

    expect(find.text('从备份恢复'), findsOneWidget);
    await tester.tap(find.text('从备份恢复'));
    // 不用 pumpAndSettle：面板里的候选枚举是真实文件 IO，
    // 在 widget test 的假时钟里不会完成（loading 圈一直转 → settle 会超时）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 面板头必须先出来（说明容器/上下文都对），候选区停在 loading 也算正常
    expect(find.text('选择要恢复的备份'), findsOneWidget);
    expect(find.text('恢复前会先备份当前数据库，任何校验不通过都会中止恢复'), findsNothing);

    // 关掉面板，页面仍然可用（按钮没被 _busy 卡死）
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final restoreButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '从备份恢复'),
    );
    expect(restoreButton.onPressed, isNotNull,
        reason: '面板关掉后 _busy 必须复位，否则用户被卡在"处理中"');
  });

  testWidgets('降级态选到空库候选：确认弹窗自动变红、按钮变「仍要覆盖」', (tester) async {
    // 降级页拿不到当前行数（current = null），但"空库覆盖"依然要拦一下。
    // 这里钉住 UI 侧确实跟着 preview.destructive 走，不需要改弹窗代码。
    final preview = RestorePreview.of(
      candidate: BackupCandidate(
        path: '/tmp/fittrack_backup_20251031_235600.sqlite',
        kind: BackupSourceKind.export,
        modifiedAt: DateTime(2025, 10, 31, 23, 56),
        sizeBytes: 138000,
        counts: BackupCounts.zero,
        userVersion: 23,
        readable: true,
      ),
      current: null,
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: RestoreConfirmDialog(preview: preview))),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('仍要覆盖'), findsOneWidget, reason: '高风险时按钮文案必须跟着变');
    expect(find.textContaining('清空'), findsWidgets);
  });
}
