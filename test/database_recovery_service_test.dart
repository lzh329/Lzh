import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/services/database_recovery_service.dart';

void main() {
  group('纯逻辑：文件名 / 升级阈值 / 日志路径', () {
    test('preRestoreFileName 带 yyyyMMdd-HHmmss 时间戳且前缀固定', () {
      final name = DatabaseRecoveryService.preRestoreFileName(
        DateTime(2025, 3, 4, 5, 6, 7),
      );
      expect(name, 'pre-restore-20250304-050607.sqlite');
    });

    test('brokenFileName 前缀固定（排查用，不删原文件）', () {
      final name = DatabaseRecoveryService.brokenFileName(
        DateTime(2025, 12, 31, 23, 59, 58),
      );
      expect(name, 'broken-20251231-235958.sqlite');
    });

    test('shouldEscalateToBackup：第 3 次起把「先存一份数据」提到主位', () {
      expect(DatabaseRecoveryService.shouldEscalateToBackup(1), isFalse);
      expect(DatabaseRecoveryService.shouldEscalateToBackup(2), isFalse);
      expect(DatabaseRecoveryService.shouldEscalateToBackup(3), isTrue);
      expect(DatabaseRecoveryService.shouldEscalateToBackup(4), isTrue);
    });

    test('journalPathsFor 给出 -wal / -shm 两条残留路径', () {
      expect(
        DatabaseRecoveryService.journalPathsFor('/data/fittrack.sqlite'),
        ['/data/fittrack.sqlite-wal', '/data/fittrack.sqlite-shm'],
      );
    });
  });

  group('真实文件 IO', () {
    late Directory root;
    late Directory docs;
    late Directory backups;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fittrack_recovery');
      docs = Directory(p.join(root.path, 'docs'));
      backups = Directory(p.join(root.path, 'docs', 'backups'));
      await docs.create(recursive: true);
      await backups.create(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    File dbFile() => File(p.join(docs.path, 'fittrack.sqlite'));

    Future<void> seedDb(String content) async {
      await dbFile().writeAsString(content);
    }

    test('backupBeforeRestore 复制当前库到 pre-restore-*.sqlite', () async {
      await seedDb('CURRENT');
      final path = await DatabaseRecoveryService.backupBeforeRestore(
        dbPath: dbFile().path,
        now: DateTime(2025, 3, 4, 5, 6, 7),
        backupDir: backups,
      );
      expect(p.basename(path), 'pre-restore-20250304-050607.sqlite');
      expect(await File(path).readAsString(), 'CURRENT');
      // 原文件不能被改动
      expect(await dbFile().readAsString(), 'CURRENT');
    });

    test('当前库不存在时 backupBeforeRestore 抛异常（恢复必须中止）', () async {
      await expectLater(
        DatabaseRecoveryService.backupBeforeRestore(
          dbPath: dbFile().path,
          backupDir: backups,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('exportBrokenDatabase 复制坏库且不删原文件', () async {
      await seedDb('BROKEN');
      final path = await DatabaseRecoveryService.exportBrokenDatabase(
        dbPath: dbFile().path,
        now: DateTime(2025, 1, 2, 3, 4, 5),
        backupDir: backups,
      );
      expect(p.basename(path), 'broken-20250102-030405.sqlite');
      expect(await File(path).readAsString(), 'BROKEN');
      expect(await dbFile().exists(), isTrue, reason: '绝不删原文件');
    });

    test('cleanupJournalFiles 删除 -wal / -shm 残留', () async {
      await seedDb('DB');
      final wal = File('${dbFile().path}-wal');
      final shm = File('${dbFile().path}-shm');
      await wal.writeAsString('stale pages');
      await shm.writeAsString('stale shm');

      final deleted =
          await DatabaseRecoveryService.cleanupJournalFiles(dbFile().path);
      expect(deleted.length, 2);
      expect(wal.existsSync(), isFalse);
      expect(shm.existsSync(), isFalse);
    });

    test('cleanupJournalFiles 在没有残留时也不抛（幂等）', () async {
      await seedDb('DB');
      expect(
        await DatabaseRecoveryService.cleanupJournalFiles(dbFile().path),
        isEmpty,
      );
    });

    test('restoreFromBackup：先备份当前库 → 覆盖 → 清 WAL', () async {
      await seedDb('OLD-OUT-OF-DATE');
      final source =
          File(p.join(backups.path, 'fittrack_backup_latest.sqlite'));
      await source.writeAsString('FROM-BACKUP');
      // 残留日志必须被清掉，否则恢复后会把旧页回放进新库
      final wal = File('${dbFile().path}-wal');
      await wal.writeAsString('stale');

      final safetyCopy = await DatabaseRecoveryService.restoreFromBackup(
        backupPath: source.path,
        dbPath: dbFile().path,
        now: DateTime(2025, 3, 4, 5, 6, 7),
        backupDir: backups,
      );

      expect(await dbFile().readAsString(), 'FROM-BACKUP');
      expect(wal.existsSync(), isFalse);
      expect(
        p.basename(safetyCopy),
        'pre-restore-20250304-050607.sqlite',
        reason: '恢复前的当前库必须另存',
      );
      expect(await File(safetyCopy).readAsString(), 'OLD-OUT-OF-DATE');
    });

    test('restoreFromBackup：备份文件不存在时抛异常且不动当前库', () async {
      await seedDb('CURRENT');
      await expectLater(
        DatabaseRecoveryService.restoreFromBackup(
          backupPath: p.join(backups.path, 'missing.sqlite'),
          dbPath: dbFile().path,
          backupDir: backups,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await dbFile().readAsString(), 'CURRENT');
    });
  });
}
