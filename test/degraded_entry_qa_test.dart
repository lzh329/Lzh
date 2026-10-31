import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/migration_failure_marker.dart';
import 'package:fittrack/features/migration/presentation/pages/migration_failure_page.dart';

/// 第二轮回归验收：降级页恢复入口的**独立性**复核。
///
/// 工程师自己有一条同类测试，这里刻意用不同角度再验一遍，避免"两边都靠
/// 同一个错误假设变绿"：
/// 1. 真的不包 `ProviderScope`（复刻 bootstrap 的返回）；
/// 2. 源码守门本身要**能红** —— 把 `degraded: true` 从临时副本里删掉，
///    守门断言必须抛 TestFailure，否则它只是一句好看的话；
/// 3. `degraded` 判断必须出现在读 `databaseProvider` **之前**（用字符位置验）。
void main() {
  MigrationFailureMarker marker() => MigrationFailureMarker(
        fromVersion: 22,
        targetVersion: 23,
        failingStep: 'createTable:weekly_report_cache',
        attemptCount: 1,
        at: DateTime(2025, 3, 4, 5, 6),
      );

  const pagePath =
      'lib/features/migration/presentation/pages/migration_failure_page.dart';
  const sheetPath =
      'lib/features/settings/presentation/widgets/database_restore_sheet.dart';

  group('降级 App 里点「从备份恢复」', () {
    testWidgets('没有 ProviderScope 也能打开来源面板，且不抛异常', (tester) async {
      // 复刻 bootstrap：「库打不开 → 直接返回 DatabaseFailureApp」，外面没有
      // 任何 ProviderScope。面板若依赖 provider 容器，这里会立刻失败。
      await tester.pumpWidget(DatabaseFailureApp(marker: marker()));
      await tester.pump();

      expect(find.text('从备份恢复'), findsOneWidget);
      await tester.tap(find.text('从备份恢复'));
      // 不用 pumpAndSettle：候选枚举是真实文件 IO，在假时钟里不会完成，
      // loading 圈会一直转（settle 必然超时）。这里只验"面板开了且没炸"。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull,
          reason: '降级态打开面板不许抛任何异常');
      expect(find.text('选择要恢复的备份'), findsOneWidget);
      expect(find.textContaining('没有找到可恢复的备份'), findsNothing,
          reason: '假时钟里 IO 还没结束，此时不该已经判定"没有备份"');

      // 关掉面板：按钮必须复位，否则用户被永久卡在"处理中"
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '从备份恢复'),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('选择要恢复的备份'), findsNothing);
    });
  });

  group('源码守门', () {
    /// 去掉注释再扫，否则"文档注释里解释旧实现叫什么"会被当成残留。
    /// 这类注释恰恰是有价值的，不应该为了测试把它们删掉。
    String codeOf(String path) {
      final buffer = StringBuffer();
      for (final line in File(path).readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        buffer.writeln(line);
      }
      return buffer.toString();
    }

    test('降级页只能用 degraded: true 打开面板，且不再自己找备份', () {
      final source = codeOf(pagePath);
      expect(source, contains('showDatabaseRestoreSheet(context, degraded: true)'));
      // 查的是**旧的盲选 API 调用**，不是裸词：页面里那个同名私有方法
      // `_restoreFromBackup()` 现在只是"打开来源面板"，不含盲选逻辑。
      expect(source, isNot(contains('DatabaseRecoveryService.findRestorableBackup')));
      expect(source, isNot(contains('DatabaseRecoveryService.restoreFromBackup')));
    });

    test('守门是"能红"的：把 degraded: true 去掉后同一条断言必须失败', () {
      final source = File(pagePath).readAsStringSync();
      // 改的是**临时副本**，仓库文件一个字节没动
      final mutated = source.replaceFirst(
        'showDatabaseRestoreSheet(context, degraded: true)',
        'showDatabaseRestoreSheet(context)',
      );
      expect(mutated, isNot(source), reason: '替换必须真的生效，否则这条实验没意义');

      final tempDir = Directory.systemTemp.createTempSync('qa_guard_probe');
      try {
        final copy = File('${tempDir.path}/migration_failure_page.dart')
          ..writeAsStringSync(mutated);
        final copySource = copy.readAsStringSync();

        // 这就是守门断言本身；它必须对"退化成非降级调用"的副本报失败。
        expect(
          () => expect(
            copySource,
            contains('showDatabaseRestoreSheet(context, degraded: true)'),
          ),
          throwsA(isA<TestFailure>()),
          reason: '如果这条不红，说明守门拦不住回退，等于没有守门',
        );
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('degraded 判断出现在读 databaseProvider 之前（否则降级态照样开坏库）', () {
      final source = codeOf(sheetPath);

      final guard = source.indexOf('if (widget.degraded) return null;');
      final read = source.indexOf('ref.read(databaseProvider)');
      expect(guard, greaterThan(-1), reason: '行数对比必须有一道 degraded 短路');
      expect(read, greaterThan(-1));
      expect(guard, lessThan(read),
          reason: '短路必须写在读 provider 之前，写在后面等于还是先开了库');

      expect(source, contains('widget.degraded ? null : _closeDatabase'),
          reason: '降级态没有可用连接，closeDatabase 必须传 null');
      expect(
        source,
        contains(
            'ProviderScope(child: DataRestoreSourceSheet(degraded: true))'),
        reason: '降级态面板必须自带容器（外面没有 ProviderScope）',
      );
    });

    test('设置页与旧服务里都没有盲选残留', () {
      final actions =
          codeOf('lib/features/settings/presentation/settings_actions.dart');
      for (final banned in [
        'Future<void> restoreDatabase',
        'findRestorableBackup',
        'restoreFromBackup',
        'DatabaseRecoveryService',
      ]) {
        expect(actions, isNot(contains(banned)),
            reason: 'settings_actions 不许出现 $banned');
      }

      final recovery = codeOf('lib/core/services/database_recovery_service.dart');
      expect(recovery, isNot(contains('findRestorableBackup')));
      expect(recovery, isNot(contains('static Future<String> restoreFromBackup')));
      // 留下来的能力不能被顺手删掉（降级页与迁移页还在用）
      for (final kept in [
        'backupBeforeRestore',
        'exportBrokenDatabase',
        'cleanupJournalFiles',
        'databasePath',
      ]) {
        expect(recovery, contains(kept), reason: '$kept 必须保留');
      }
    });

    test('lib 下不再有盲选 API 的任何调用点', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final code = codeOf(entity.path);
        if (code.contains('findRestorableBackup') ||
            code.contains('DatabaseRecoveryService.restoreFromBackup')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '盲选 API 必须彻底消失，不能只从设置页搬走：$offenders');
    });

    test('旧的盲选实现连测试都一起删了（留着会给人"还能用"的错觉）', () {
      final testSource =
          codeOf('test/database_recovery_service_test.dart');
      expect(testSource, isNot(contains('DatabaseRecoveryService.restoreFromBackup')));
      expect(testSource, isNot(contains('findRestorableBackup')));
    });
  });
}
