import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/services/restore_service.dart';

/// 造一个真实库并写入 [count] 条 body_metrics
Future<void> seedDb(File dbFile, {int count = 2}) async {
  final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
  await db.customSelect('SELECT 1').get();
  for (var i = 0; i < count; i++) {
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
          date: DateTime(2025, 3, 1 + i),
          weightKg: 70.0 + i,
        ));
  }
  await db.close();
}

Future<int> dbRowCount(File dbFile) async {
  final db = AppDatabase.withExecutor(
    NativeDatabase(dbFile, enableMigrations: false),
  );
  final row =
      await db.customSelect('SELECT COUNT(*) AS c FROM body_metrics').getSingle();
  await db.close();
  return (row.data['c'] as num).toInt();
}

/// 改 user_version，模拟"来自更新版本 App 的备份"
Future<void> setUserVersion(File dbFile, int version) async {
  final db = AppDatabase.withExecutor(
    NativeDatabase(dbFile, enableMigrations: false),
  );
  await db.customStatement('PRAGMA user_version = $version');
  await db.close();
}

void main() {
  late Directory root;
  late Directory docs;
  late Directory downloads;
  late Directory photos;
  late Directory backups;
  late File dbFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fittrack_raw_restore');
    docs = Directory(p.join(root.path, 'docs'));
    downloads = Directory(p.join(root.path, 'downloads'));
    photos = Directory(p.join(docs.path, 'photos'));
    backups = Directory(p.join(docs.path, 'backups'));
    await downloads.create(recursive: true);
    await photos.create(recursive: true);
    await backups.create(recursive: true);
    dbFile = File(p.join(docs.path, 'fittrack.sqlite'));
  });

  tearDown(() async {
    DatabaseSeal.reset();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<File> exportedBackup({int count = 3}) async {
    final file = File(p.join(downloads.path, 'fittrack_backup_20251031_235600.sqlite'));
    await seedDb(file, count: count);
    return file;
  }

  group('裸 .sqlite 恢复（导出文件 / 自动备份 / 恢复前副本）', () {
    test('恢复成功：新库内容与候选一致，旧库另存为 pre-restore', () async {
      final source = await exportedBackup(count: 3);
      await seedDb(dbFile, count: 1);
      await File(p.join(photos.path, 'keep.jpg')).writeAsBytes([7]);

      final result = await RestoreService.restoreDatabaseFile(
        sourcePath: source.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
        now: DateTime(2025, 11, 1, 1, 2, 3),
      );

      expect(await dbRowCount(dbFile), 3, reason: '必须真的用上用户选的那份');
      expect(p.basename(result.preRestorePath),
          'pre-restore-20251101-010203.sqlite');
      expect(File(result.preRestorePath).existsSync(), isTrue,
          reason: '旧库只能 rename 保留，绝不 delete');
      expect(await dbRowCount(File(result.preRestorePath)), 1,
          reason: '恢复前的数据必须能在 pre-restore 里找回');
      expect(File(result.preRestoreArchivePath).existsSync(), isTrue,
          reason: '恢复前必须强制打一份完整备份包');
      expect(DatabaseSeal.sealed, isTrue,
          reason: '成功后保持封存，逼用户重启，避免继续读写旧句柄');
    });

    test('裸库没有照片：现有 photos 目录不被清空', () async {
      final source = await exportedBackup(count: 2);
      await seedDb(dbFile, count: 1);
      final photo = File(p.join(photos.path, 'keep.jpg'));
      await photo.writeAsBytes([7]);

      await RestoreService.restoreDatabaseFile(
        sourcePath: source.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

      expect(photo.existsSync(), isTrue,
          reason: '纯 .sqlite 里没有照片，恢复不能把现有照片删掉');
    });

    test('文件头读不出（损坏文件）→ 中止，原库一个字节都不动', () async {
      final source =
          File(p.join(downloads.path, 'fittrack_backup_20251031_235600.sqlite'));
      await source.writeAsBytes([1, 2, 3, 4]);
      await seedDb(dbFile, count: 1);
      final before = await dbFile.readAsBytes();

      await expectLater(
        RestoreService.restoreDatabaseFile(
          sourcePath: source.path,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('文件头'))),
      );

      expect(await dbFile.readAsBytes(), before, reason: '原库必须没被碰过');
      expect(await dbRowCount(dbFile), 1);
    });

    test('user_version 高于当前 → 拒绝（不打开、不迁移、不覆盖）', () async {
      final source = await exportedBackup(count: 3);
      await setUserVersion(source, kSchemaVersion + 1);
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreDatabaseFile(
          sourcePath: source.path,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('更新版本'))),
      );

      expect(await dbRowCount(dbFile), 1);
    });

    test('关键表缺失（不是本 App 的库）→ 中止并点名缺哪张表', () async {
      final source = await exportedBackup(count: 3);
      final db = AppDatabase.withExecutor(
        NativeDatabase(source, enableMigrations: false),
      );
      await db.customStatement('DROP TABLE photos');
      await db.close();
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreDatabaseFile(
          sourcePath: source.path,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('photos'))),
      );

      expect(await dbRowCount(dbFile), 1);
    });

    test('当前库不存在 → 备份阶段失败即中止（不允许裸覆盖）', () async {
      final source = await exportedBackup(count: 3);
      // 不建 dbFile：恢复前的强制备份会失败
      await expectLater(
        RestoreService.restoreDatabaseFile(
          sourcePath: source.path,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()),
      );
      expect(dbFile.existsSync(), isFalse, reason: '没备份就绝不创建/覆盖库');
    });

    test('候选文件不存在 → 中止且不动原库', () async {
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreDatabaseFile(
          sourcePath: p.join(downloads.path, 'missing.sqlite'),
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()),
      );
      expect(await dbRowCount(dbFile), 1);
    });

    test('恢复不修改候选原件（用户手上的备份必须原样保留）', () async {
      final source = await exportedBackup(count: 3);
      final bytesBefore = await source.readAsBytes();
      await seedDb(dbFile, count: 1);

      await RestoreService.restoreDatabaseFile(
        sourcePath: source.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

      expect(await source.readAsBytes(), bytesBefore);
      expect(File('${source.path}-journal').existsSync(), isFalse);
      expect(File('${source.path}-wal').existsSync(), isFalse);
    });

    test('当前库本身打不开（降级态）也能恢复：备份走原样搬运，坏库留档', () async {
      // 降级页的真实现场：库文件在，但打不开（迁移失败 / 损坏）
      final source = await exportedBackup(count: 2);
      await dbFile.writeAsBytes(List<int>.filled(8192, 0x42));

      final result = await RestoreService.restoreDatabaseFile(
        sourcePath: source.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

      expect(await dbRowCount(dbFile), 2,
          reason: '坏库也能被替换成用户选的那份');
      expect(File(result.preRestorePath).existsSync(), isTrue,
          reason: '打不开的旧库必须原样留档，否则连排查现场都没了');
      expect(DatabaseSeal.sealed, isTrue);
    });
  });
}
