import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/backup_service.dart';
import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/restore_service.dart';

/// 建一个真实库并写入 [count] 条 body_metrics
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
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM body_metrics')
      .getSingle();
  await db.close();
  return (row.data['c'] as num).toInt();
}

/// 重写 zip 里的 manifest（制造各种不一致现场）
///
/// 注意：`Archive.files` 是不可修改列表，必须新建一个 Archive 重新打包。
Future<void> rewriteManifest(
  String zipPath,
  void Function(Map<String, dynamic>) edit,
) async {
  final entries = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
  final manifestEntry =
      entries.files.firstWhere((f) => f.name == 'manifest.json');
  final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>))
      as Map<String, dynamic>;
  edit(manifest);

  final rebuilt = Archive();
  for (final entry in entries.files) {
    if (entry.name == 'manifest.json') {
      final bytes = utf8.encode(jsonEncode(manifest));
      rebuilt.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
    } else {
      rebuilt.addFile(entry);
    }
  }

  final patched = File('$zipPath.patched');
  await patched.writeAsBytes(ZipEncoder().encode(rebuilt)!, flush: true);
  await patched.rename(zipPath);
}

void main() {
  late Directory root;
  late Directory docs;
  late Directory photos;
  late Directory backups;
  late File dbFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fittrack_restore');
    docs = Directory(p.join(root.path, 'docs'));
    photos = Directory(p.join(docs.path, 'photos'));
    backups = Directory(p.join(docs.path, 'backups'));
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

  Future<String> makeArchive(
      {int count = 2, Map<String, int>? counts, int photoCount = 1}) async {
    await seedDb(dbFile, count: count);
    for (var i = 0; i < photoCount; i++) {
      await File(p.join(photos.path, 'p$i.jpg')).writeAsBytes([i]);
    }
    final archive = await BackupService.createArchive(
      dbPath: dbFile.path,
      photosDir: photos,
      outputDir: backups,
      tableCounts: counts,
    );
    return archive.path;
  }

  group('正常路径', () {
    test('恢复成功后数据被替换、旧库另存为 pre-restore、照片导回', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      // 现在把当前库改成只有 1 条，模拟"用户要回到 3 条那个版本"
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await File(p.join(photos.path, 'p0.jpg')).delete();

      final result = await RestoreService.restoreArchive(
        archivePath: archivePath,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
        now: DateTime(2025, 3, 4, 5, 6, 7),
      );

      expect(await dbRowCount(dbFile), 3);
      expect(p.basename(result.preRestorePath),
          'pre-restore-20250304-050607.sqlite');
      expect(File(result.preRestorePath).existsSync(), isTrue,
          reason: '旧库必须 rename 保留，失败路径只允许保留不允许 delete');
      expect(await File(p.join(photos.path, 'p0.jpg')).exists(), isTrue);
      expect(result.photoCount, 1);
      expect(File(result.preRestoreArchivePath).existsSync(), isTrue,
          reason: '恢复前必须强制打一份完整包');
    });

    test('恢复前强制备份：当前库不存在时不会静默跳过', () async {
      final archivePath = await makeArchive();
      await dbFile.delete();
      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(anything),
        reason: '不允许在"当前数据没备份"的状态下动库',
      );
    });
  });

  group('校验链（失败时原库必须没被碰过）', () {
    test('空间不足 → Step 0 直接中止，库里数据不变', () async {
      final archivePath = await makeArchive(count: 3);
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
          freeSpace: () async => 1, // 1 字节可用
        ),
        throwsA(isA<RestoreAborted>()),
      );
      expect(await dbRowCount(dbFile), 1, reason: '原库不能被碰过');
    });

    test('manifest 里某张表行数对不上 → 整体中止并点名表名', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      // 把 manifest 里的行数改小 1
      await rewriteManifest(archivePath, (m) {
        (m['tableCounts'] as Map<String, dynamic>)['body_metrics'] = 2;
      });

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.table, 'table', 'body_metrics')),
      );
      expect(await dbRowCount(dbFile), 1, reason: '不允许"部分恢复成功"：校验失败必须整体中止');
    });

    test('tableCounts 缺失（降级包）→ 警告放行，不判失败', () async {
      final archivePath = await makeArchive(count: 3); // 不传 counts
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      final result = await RestoreService.restoreArchive(
        archivePath: archivePath,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );
      expect(await dbRowCount(dbFile), 3);
      expect(result.warnings, isNotEmpty, reason: '旧版备份必须给可见提示，不能静默当成正常包');
      expect(result.warnings.join(), contains('行数校验'));
    });

    test('manifest 声称来自更新版本 → 拒绝（不覆盖当前数据）', () async {
      final archivePath = await makeArchive(count: 3);
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await rewriteManifest(archivePath, (m) {
        m['schemaVersion'] = kSchemaVersion + 1;
      });

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>().having(
          (e) => e.reason,
          'reason',
          contains('更新版本'),
        )),
      );
      expect(await dbRowCount(dbFile), 1);
    });

    test('照片数量对不上 → 中止', () async {
      final archivePath = await makeArchive(count: 3, photoCount: 2);
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await rewriteManifest(archivePath, (m) {
        m['photoCount'] = 5;
      });

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>().having(
          (e) => e.reason,
          'reason',
          contains('照片'),
        )),
      );
      expect(await dbRowCount(dbFile), 1);
    });

    test('备份包损坏 → 中止且原库不动', () async {
      final archivePath = await makeArchive(count: 3);
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await File(archivePath).writeAsBytes([1, 2, 3, 4]);

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(anything),
      );
      expect(await dbRowCount(dbFile), 1);
    });

    test('恢复后清掉 -wal/-shm 残留（避免旧页回放进新库）', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await File('${dbFile.path}-wal').writeAsBytes([9, 9]);
      await File('${dbFile.path}-shm').writeAsBytes([8, 8]);

      await RestoreService.restoreArchive(
        archivePath: archivePath,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

      expect(File('${dbFile.path}-wal').existsSync(), isFalse);
      expect(File('${dbFile.path}-shm').existsSync(), isFalse);
      expect(await dbRowCount(dbFile), 3);
    });
  });

  group('db_replaced 标记与封存', () {
    test('恢复成功后标记已清、但**保持封存**（顺序：写标记→close→rename→seal→校验→清标记）', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      var closedCalled = 0;
      await RestoreService.restoreArchive(
        archivePath: archivePath,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
        closeDatabase: () async => closedCalled++,
      );

      expect(closedCalled, 1, reason: '真正的保护是 rename 前 close 连接');
      expect(
        await DbReplacedMarker.exists(baseDir: docs),
        isFalse,
        reason: '新库校验通过后才清标记；成功后不该残留',
      );
      expect(
        DatabaseSeal.sealed,
        isTrue,
        reason: '成功后**保持封存**：本进程的 provider 仍持有旧库引用，'
            '解除封存等于允许用旧缓存读写新库',
      );
    });

    test('恢复失败（校验链中止）不写标记、不封存', () async {
      final archivePath = await makeArchive(count: 3);
      await dbFile.delete();
      await seedDb(dbFile, count: 1);
      await rewriteManifest(archivePath, (m) {
        m['schemaVersion'] = kSchemaVersion + 5;
      });

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
        ),
        throwsA(isA<RestoreAborted>()),
      );

      expect(
        await DbReplacedMarker.exists(baseDir: docs),
        isFalse,
        reason: '失败路径不写标记：没换过库就不该让用户以为换过',
      );
      expect(DatabaseSeal.sealed, isFalse);
    });
  });

  group('崩溃注入：标记 + 封存必须能自愈', () {
    test('rename 前崩 → 库还是恢复前那份、标记在 → 消解后可用', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
          onBeforeRename: () async => throw StateError('process killed'),
        ),
        throwsA(anything),
      );

      expect(await dbRowCount(dbFile), 1, reason: '还没 rename，库必须是恢复前那份');
      expect(
        await DbReplacedMarker.exists(baseDir: docs),
        isTrue,
        reason: '标记在 rename 之前写，所以崩在 rename 前也会留下标记 —— '
            '下次启动重建一次即可，不会误判成"已换库"',
      );

      // 重启语义：清封存后重新打开，能正常读写
      DatabaseSeal.reset();
      final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      expect((await db.select(db.bodyMetrics).get()).length, 1);
      await db.close();
    });

    test('rename 后崩 → 库已是新库、标记在 → 消解后可用', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      await expectLater(
        RestoreService.restoreArchive(
          archivePath: archivePath,
          dbPath: dbFile.path,
          photosDir: photos,
          backupDir: backups,
          docsDir: docs,
          onAfterRename: () async => throw StateError('process killed'),
        ),
        throwsA(anything),
      );

      expect(await dbRowCount(dbFile), 3, reason: 'rename 已发生，库是新的');
      expect(await DbReplacedMarker.exists(baseDir: docs), isTrue);

      DatabaseSeal.reset();
      final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
      await db.customSelect('SELECT 1').get();
      expect((await db.select(db.bodyMetrics).get()).length, 3);
      await db.close();
    });

    test('恢复成功后直接走 provider → 抛 StateError（写保护生效）', () async {
      final archivePath =
          await makeArchive(count: 3, counts: {'body_metrics': 3});
      await dbFile.delete();
      await seedDb(dbFile, count: 1);

      await RestoreService.restoreArchive(
        archivePath: archivePath,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await expectLater(
        Future.sync(() => container.read(databaseProvider)),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('请重启'),
        )),
        reason: '封存态下任何 provider 取库都必须失败，否则会拿旧缓存写新库',
      );
    });
  });

  group('pre-restore 生命周期', () {
    test('最多保留 2 份，且不占用 keep=4 的自动备份额度', () async {
      for (var i = 0; i < 4; i++) {
        await File(p.join(
                backups.path, 'pre-restore-2025030${i + 1}-000000.sqlite'))
            .writeAsBytes([i]);
      }
      await File(p.join(backups.path, 'fittrack_backup_20250301-000000.zip'))
          .writeAsBytes([1]);

      await RestoreService.prunePreRestore(backupDir: backups);

      final preRestore = (await backups.list().toList())
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('pre-restore-'))
          .toList();
      expect(preRestore.length, 2, reason: '保留最近 2 份');
      expect(
          File(p.join(backups.path, 'fittrack_backup_20250301-000000.zip'))
              .existsSync(),
          isTrue,
          reason: 'pre-restore 清理不能动自动备份');
    });

    test('latestPreRestore 返回最新一份', () async {
      await File(p.join(backups.path, 'pre-restore-20250301-000000.sqlite'))
          .writeAsBytes([1]);
      await File(p.join(backups.path, 'pre-restore-20250309-000000.sqlite'))
          .writeAsBytes([2]);

      final latest = await RestoreService.latestPreRestore(backupDir: backups);
      expect(p.basename(latest!), 'pre-restore-20250309-000000.sqlite');
    });

    test('没有 pre-restore 时 latestPreRestore 返回 null', () async {
      expect(await RestoreService.latestPreRestore(backupDir: backups), isNull);
    });
  });
}
