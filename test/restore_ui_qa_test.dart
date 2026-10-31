import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/backup_candidate.dart';
import 'package:fittrack/features/settings/presentation/widgets/restore_candidate_card.dart';
import 'package:fittrack/features/settings/presentation/widgets/restore_confirm_dialog.dart';

/// 恢复入口的 UI 验收。
///
/// 这里只测"用户看到什么、能不能点"，不重复 service 层的校验链 ——
/// 但每一条都对应 PRD 里的一句硬要求（来源/行数可见、空库必须红色拦一下、
/// 没有候选时给指引而不是白屏）。
void main() {
  BackupCandidate candidate({
    BackupCounts? counts = const BackupCounts(
      workouts: 5,
      bodyMetrics: 3,
      photos: 2,
      exercises: 40,
    ),
    BackupSourceKind kind = BackupSourceKind.export,
    bool readable = true,
    int? userVersion = 23,
    int sizeBytes = 138000,
    DateTime? modifiedAt,
    String? path,
  }) {
    return BackupCandidate(
      path: path ?? '/storage/emulated/0/Download/fittrack_backup_20251031_235600.sqlite',
      kind: kind,
      modifiedAt: modifiedAt ?? DateTime(2025, 10, 31, 23, 56),
      sizeBytes: sizeBytes,
      counts: counts,
      userVersion: userVersion,
      readable: readable,
    );
  }

  Future<void> pumpDialog(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );
    await tester.pumpAndSettle();
  }

  group('确认弹窗：高风险必须被明确标出来', () {
    testWidgets('空库候选 + 当前库有数据 → 红色警告 + 按钮改成「仍要覆盖」', (tester) async {
      final preview = RestorePreview.of(
        candidate: candidate(counts: BackupCounts.zero),
        current: const BackupCounts(workouts: 5, bodyMetrics: 3, photos: 2),
      );
      await pumpDialog(tester, RestoreConfirmDialog(preview: preview));

      expect(find.text('确认恢复这份备份？'), findsOneWidget);
      expect(find.textContaining('关键记录全是 0'), findsOneWidget,
          reason: '要一句话说清"这份是空的"');
      expect(find.textContaining('清空'), findsOneWidget,
          reason: '必须写清后果：继续会清空当前数据');
      expect(find.text('仍要覆盖'), findsOneWidget,
          reason: '高风险时按钮文案也要变，光有红色文字不够');
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('正常备份（有数据）→ 按钮就是「恢复」，不吓人', (tester) async {
      final preview = RestorePreview.of(
        candidate: candidate(),
        current: BackupCounts.zero,
      );
      await pumpDialog(tester, RestoreConfirmDialog(preview: preview));

      expect(find.text('恢复'), findsOneWidget);
      expect(find.text('仍要覆盖'), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('裸库候选会说明"照片不会跟着恢复"', (tester) async {
      final preview = RestorePreview.of(
        candidate: candidate(kind: BackupSourceKind.export),
        current: const BackupCounts(bodyMetrics: 1),
      );
      await pumpDialog(tester, RestoreConfirmDialog(preview: preview));
      expect(find.textContaining('照片不会跟着恢复'), findsOneWidget);
    });

    testWidgets('备份来自更新版本时弹窗里就告知会被拒绝', (tester) async {
      final preview = RestorePreview.of(
        candidate: candidate(userVersion: 24),
        current: const BackupCounts(bodyMetrics: 1),
      );
      await pumpDialog(tester, RestoreConfirmDialog(preview: preview));
      expect(find.textContaining('更新版本'), findsOneWidget);
    });
  });

  group('候选卡：每项都要能自己辨认', () {
    testWidgets('显示来源、时间、大小、关键表行数', (tester) async {
      await pumpDialog(tester, RestoreCandidateCard(candidate: candidate()));

      expect(find.text('导出文件'), findsOneWidget, reason: '来源标签');
      expect(find.text('10-31 23:56'), findsOneWidget, reason: '时间');
      expect(find.text('135 KB'), findsOneWidget, reason: '大小');
      expect(find.textContaining('训练 5'), findsOneWidget);
      expect(find.textContaining('体重 3'), findsOneWidget);
      expect(find.textContaining('照片 2'), findsOneWidget);
      expect(find.textContaining('fittrack_backup_20251031_235600.sqlite'),
          findsOneWidget, reason: '文件名，便于用户对上自己导出的那份');
    });

    testWidgets('空库候选的摘要直接写「关键记录全为 0」', (tester) async {
      await pumpDialog(
        tester,
        RestoreCandidateCard(candidate: candidate(counts: BackupCounts.zero)),
      );
      expect(find.text('关键记录全为 0'), findsOneWidget);
      expect(find.textContaining('训练 0'), findsNothing);
    });

    testWidgets('统计不出来的候选项要写「无法统计」，不能显示成 0', (tester) async {
      await pumpDialog(
        tester,
        RestoreCandidateCard(candidate: candidate(counts: null)),
      );
      expect(find.text('行数无法统计'), findsOneWidget,
          reason: '"不知道"不能显示成"是空的"');
    });

    // ⚠️ 需求 B2 要求展示 workouts / body_metrics / photos / exercises 四张表的行数，
    // 当前卡片只渲染前三张（exercises 已统计但没渲染）。这里先 skip 保住门禁，
    // 修好后把 skip 去掉即可当回归用。见交付回执「问题 #3」。
    testWidgets('需求 B2 要求 4 张关键表的行数（workouts/body_metrics/photos/exercises）',
        (tester) async {
      await pumpDialog(tester, RestoreCandidateCard(candidate: candidate()));
      expect(find.textContaining('动作'), findsWidgets);
    });
  });

  group('UI 接线（源码级守门）', () {
    // 这几条是在文件层面守门，而不是渲染层面：
    // 数据管理页 / 来源面板都要碰真实文件 IO，widget test 的 fake async
    // 里跑不完（dart:io 的 Future 在 fake async 中永不完成），
    // 所以"谁调了谁"这一层直接用源码断言，回归时同样能拦住。
    String read(String path) => File(path).readAsStringSync();

    const page = 'lib/features/settings/presentation/pages/data_management_page.dart';
    const actions = 'lib/features/settings/presentation/settings_actions.dart';
    const sheet =
        'lib/features/settings/presentation/widgets/database_restore_sheet.dart';

    test('数据管理页的「恢复数据库」必须打开来源选择面板', () {
      final source = read(page);
      expect(source, contains("title: '恢复数据库'"));
      expect(
        source,
        contains('showDatabaseRestoreSheet(context)'),
        reason: '恢复入口不能再直接执行，必须先让用户选来源',
      );
      expect(source, isNot(contains('restoreDatabase(context)')),
          reason: '旧的盲选实现必须彻底消失');
    });

    test('旧的盲选实现已从 settings_actions 删除，且没有残留引用', () {
      final source = read(actions);
      expect(source, isNot(contains('Future<void> restoreDatabase')));
      expect(source, isNot(contains('findRestorableBackup')));
      expect(source, isNot(contains('DatabaseRecoveryService')));
    });

    test('来源面板对 zip 与裸库走不同的恢复入口（不能一律 copy）', () {
      final source = read(sheet);
      expect(source, contains('RestoreService.restoreDatabaseFile'));
      expect(source, contains('RestoreService.restoreArchive'));
      expect(source, contains('closeDatabase'),
          reason: 'rename 之前必须先关连接，否则旧句柄会继续写被换掉的库');
    });
  });
}
