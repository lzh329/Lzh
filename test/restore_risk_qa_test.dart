import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/services/backup_candidate_service.dart';
import 'package:fittrack/core/services/restore_service.dart';

/// QA 独立验收（不做实现自述的转述，只测"会不会二次丢数据"）。
///
/// 关注三件事：
/// 1. **原子性**：候选库坏掉 / 版本不对 / 缺表时，当前库的字节必须一模一样；
/// 2. **探测不污染**：列候选列表不能碰用户手上的备份原件（含 mtime / 旁文件）；
/// 3. **照片不误删**：裸 `.sqlite` 里没有照片，现有 `photos/` 必须原样留着。
///
/// 只用真实文件（不用 memory 库）：这次事故的全部难点都在"文件"上，
/// 内存库会让 rename / 旁文件 / 截断这三类问题整体消失。

Future<void> seedDb(File file, {int rows = 0, String note = ''}) async {
  final db = AppDatabase.withExecutor(NativeDatabase(file));
  await db.customSelect('SELECT 1').get();
  for (var i = 0; i < rows; i++) {
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
          date: DateTime(2025, 1, 1).add(Duration(days: i)),
          weightKg: 60 + i % 20,
          note: Value(note),
        ));
  }
  await db.close();
}

Future<int> bodyMetricRows(File file) async {
  final db = AppDatabase.withExecutor(
    NativeDatabase(file, enableMigrations: false),
  );
  try {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM body_metrics')
        .getSingle();
    return (row.data['c'] as num).toInt();
  } finally {
    await db.close();
  }
}

Future<int?> userVersionOf(File file) async {
  final db = AppDatabase.withExecutor(
    NativeDatabase(file, enableMigrations: false),
  );
  try {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return (row.data.values.first as num).toInt();
  } finally {
    await db.close();
  }
}

Future<void> setUserVersion(File file, int version) async {
  final db = AppDatabase.withExecutor(
    NativeDatabase(file, enableMigrations: false),
  );
  await db.customStatement('PRAGMA user_version = $version');
  await db.close();
}

Future<String> sha256Of(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

void main() {
  late Directory root;
  late Directory docs;
  late Directory downloads;
  late Directory photos;
  late Directory backups;
  late File dbFile;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fittrack_qa_restore');
    docs = Directory(p.join(root.path, 'docs'));
    downloads = Directory(p.join(root.path, 'downloads'));
    photos = Directory(p.join(docs.path, 'photos'));
    backups = Directory(p.join(docs.path, 'backups'));
    await photos.create(recursive: true);
    await backups.create(recursive: true);
    await downloads.create(recursive: true);
    dbFile = File(p.join(docs.path, 'fittrack.sqlite'));
  });

  tearDown(() async {
    DatabaseSeal.reset();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  });

  /// 用户刚导出的那份（Download 目录）
  Future<File> exported({int rows = 3}) async {
    final file = File(
      p.join(downloads.path, 'fittrack_backup_20251031_235600.sqlite'),
    );
    await seedDb(file, rows: rows, note: 'x' * 120);
    return file;
  }

  /// 造一份"当前库"，并返回它的 sha256
  Future<String> seedCurrent({int rows = 2}) async {
    await seedDb(dbFile, rows: rows, note: 'y' * 120);
    return sha256Of(dbFile);
  }

  Future<RestoreResult> restore(File source) => RestoreService.restoreDatabaseFile(
        sourcePath: source.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
      );

  // ─────────────────────────────────────────────────────────────
  // 1. 原子性：坏候选 / 错版本 / 缺表 → 当前库字节必须一模一样
  // ─────────────────────────────────────────────────────────────
  group('原子性：任何预检失败，当前库一个字节都不动', () {
    /// 三种"看起来像数据库"的坏文件：
    /// 截断（文件头声称的页数比实际多）、坏页（页内容全 0xFF）、
    /// 伪头（真文件头 + 垃圾体）。三者都能骗过"看魔数"这一关，
    /// 只有 integrity_check 才拦得住 —— 这正是需要守住的位置。
    Future<void> expectRejectedWithoutTouching(
      Future<void> Function(File corrupt) make,
      String label,
    ) async {
      final source = await exported(rows: 40);
      await make(source);
      final before = await seedCurrent(rows: 2);

      await expectLater(
        restore(source),
        throwsA(isA<RestoreAborted>()),
        reason: '$label：必须中止，不能把坏库盖上去',
      );

      expect(await sha256Of(dbFile), before, reason: '$label：当前库必须没被碰过');
      expect(await bodyMetricRows(dbFile), 2, reason: '$label：行数还是原来的');
      expect(
        DatabaseSeal.sealed,
        isFalse,
        reason: '$label：失败不许封存（否则用户被卡在"请重启"里）',
      );
      expect(
        await DbReplacedMarker.exists(baseDir: docs),
        isFalse,
        reason: '$label：失败不许写 db_replaced 标记',
      );
      expect(
        backups.listSync().whereType<File>().where(
              (f) => p.basename(f.path).startsWith('pre-restore-'),
            ),
        isEmpty,
        reason: '$label：失败连 pre-restore 都不该产生（rename 根本没发生）',
      );
    }

    test('候选库被截断（头完好、尾缺失）→ 中止 + 当前库 sha256 不变', () async {
      await expectRejectedWithoutTouching((file) async {
        final bytes = await file.readAsBytes();
        expect(bytes.length, greaterThan(3 * 4096),
            reason: '样本必须跨多页，否则截断测不出问题');
        await file.writeAsBytes(bytes.sublist(0, 3 * 4096 + 100));
      }, '截断');
    });

    test('候选库中间页被写坏 → 中止 + 当前库 sha256 不变', () async {
      await expectRejectedWithoutTouching((file) async {
        final bytes = await file.readAsBytes();
        // 跳过第 1 页（sqlite_master 在里面，写坏它会退化成"打不开"，
        // 我们希望覆盖的是"能打开但内容坏了"这一档）
        const from = 4096 * 2;
        expect(bytes.length, greaterThan(from + 1024));
        final corrupted = List<int>.from(bytes);
        for (var i = from; i < from + 1024; i++) {
          corrupted[i] = 0xFF;
        }
        await file.writeAsBytes(corrupted);
      }, '坏页');
    });

    test('候选文件只有正确的 100 字节头 + 垃圾 → 中止 + 当前库 sha256 不变', () async {
      await expectRejectedWithoutTouching((file) async {
        final valid = await file.readAsBytes();
        final fake = <int>[...valid.sublist(0, 100), ...List<int>.filled(8192, 0)];
        await file.writeAsBytes(fake);
      }, '伪头');
    });

    test('候选 user_version 比 App 新 → 拒绝，且不打开候选、不迁移、当前库不变', () async {
      final source = await exported(rows: 5);
      await setUserVersion(source, kSchemaVersion + 1);
      final sourceBytes = await source.readAsBytes();
      final before = await seedCurrent();

      await expectLater(
        restore(source),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('更新版本'))),
      );

      expect(await sha256Of(dbFile), before);
      expect(await source.readAsBytes(), sourceBytes, reason: '候选原件不能被改');
    });

    test('候选是别的 App 的合法 sqlite（缺关键表）→ 拒绝并点名缺哪张表', () async {
      final source =
          File(p.join(downloads.path, 'fittrack_backup_20251031_235600.sqlite'));
      final other = AppDatabase.withExecutor(NativeDatabase(source));
      await other.customSelect('SELECT 1').get();
      await other.customStatement('DROP TABLE photos');
      await other.close();
      final before = await seedCurrent();

      await expectLater(
        restore(source),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('photos'))),
      );
      expect(await sha256Of(dbFile), before);
    });

    test('候选文件被删掉 → 中止且当前库不变', () async {
      final before = await seedCurrent();
      await expectLater(
        restore(File(p.join(downloads.path, 'gone.sqlite'))),
        throwsA(isA<RestoreAborted>()
            .having((e) => e.reason, 'reason', contains('不在'))),
      );
      expect(await sha256Of(dbFile), before);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 2. 探测不污染：列候选 = 只读，原件大小 / mtime / 内容都不许变
  // ─────────────────────────────────────────────────────────────
  group('候选探测不污染原件', () {
    test('文件大小 / mtime / sha256 都不变，且不留下 -wal/-journal/-shm', () async {
      final file = await exported(rows: 5);
      final stamp = DateTime(2025, 10, 31, 23, 56);
      await file.setLastModified(stamp);

      final lengthBefore = await file.length();
      final mtimeBefore = await file.lastModified();
      final hashBefore = await sha256Of(file);

      final list = await BackupCandidateService.listCandidates(
        docsDir: docs,
        downloadDir: downloads,
        backupsDir: backups,
      );

      expect(list, isNotEmpty);
      expect(list.single.readable, isTrue);
      expect(list.single.counts!.bodyMetrics, 5, reason: '行数必须真的数出来');

      expect(await file.length(), lengthBefore, reason: '探测不能改原件大小');
      expect(await file.lastModified(), mtimeBefore, reason: '探测不能改 mtime');
      expect(await sha256Of(file), hashBefore, reason: '探测不能改原件内容');
      for (final side in ['-wal', '-shm', '-journal']) {
        expect(File('${file.path}$side').existsSync(), isFalse,
            reason: '打开候选库不能把 $side 落在用户目录里');
      }
    });

    test('候选旁边原本就有 -wal 时，探测既不删也不改它', () async {
      final file = await exported(rows: 2);
      final wal = File('${file.path}-wal');
      await wal.writeAsBytes([1, 2, 3]);
      final walBytes = await wal.readAsBytes();

      await BackupCandidateService.listCandidates(
        docsDir: docs,
        downloadDir: downloads,
        backupsDir: backups,
      );

      expect(await wal.exists(), isTrue, reason: '旁文件属于用户的备份，不许动');
      expect(await wal.readAsBytes(), walBytes);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 3. 候选枚举的边界
  // ─────────────────────────────────────────────────────────────
  group('候选枚举', () {
    test('当前正在用的 fittrack.sqlite 不会出现在候选里', () async {
      await seedCurrent(rows: 3);
      final list = await BackupCandidateService.listCandidates(
        docsDir: docs,
        downloadDir: downloads,
        backupsDir: backups,
      );
      expect(
        list.map((c) => p.canonicalize(c.path)),
        isNot(contains(p.canonicalize(dbFile.path))),
        reason: '把"正在用的库"列成候选，等于让用户用一种很绕的方式覆盖自己',
      );
      expect(list, isEmpty);
    });

    test('四类来源（Download 导出 / 文档根导出 / 自动备份 / 恢复前副本 / 包）都能列出', () async {
      // mtime 必须显式写成不同的值：测试跑得快，同一毫秒内建出来的文件
      // mtime 完全相等，排序会退化成"按路径倒序"，测不到真实排序意图。
      final inDownload = File(
        p.join(downloads.path, 'fittrack_backup_20251030_100000.sqlite'),
      );
      final inDocsRoot =
          File(p.join(docs.path, 'fittrack_backup_20251029_100000.sqlite'));
      final inBackups =
          File(p.join(backups.path, 'fittrack_backup_20251028_100000.sqlite'));
      final preRestore =
          File(p.join(backups.path, 'pre-restore-20251027-100000.sqlite'));
      await seedDb(inDownload, rows: 1);
      await seedDb(inDocsRoot, rows: 1);
      await seedDb(inBackups, rows: 1);
      await seedDb(preRestore, rows: 1);
      await inDownload.setLastModified(DateTime(2025, 10, 30, 10));
      await inDocsRoot.setLastModified(DateTime(2025, 10, 29, 10));
      await inBackups.setLastModified(DateTime(2025, 10, 28, 10));
      await preRestore.setLastModified(DateTime(2025, 10, 27, 10));

      final list = await BackupCandidateService.listCandidates(
        docsDir: docs,
        downloadDir: downloads,
        backupsDir: backups,
      );

      expect(list.map((c) => c.kind).toSet(), {
        BackupSourceKind.export,
        BackupSourceKind.autoBackup,
        BackupSourceKind.preRestore,
      });
      expect(list.length, 4);
      expect(
        list.map((c) => c.fileName).toList(),
        [
          'fittrack_backup_20251030_100000.sqlite',
          'fittrack_backup_20251029_100000.sqlite',
          'fittrack_backup_20251028_100000.sqlite',
          'pre-restore-20251027-100000.sqlite',
        ],
        reason: '按 mtime 倒序：最近的那份排最前',
      );
    });

    test('所有来源都读不到时返回空列表，不抛异常（恢复入口不能因此打不开）', () async {
      final list = await BackupCandidateService.listCandidates(
        docsDir: Directory(p.join(root.path, 'no-docs')),
        downloadDir: Directory(p.join(root.path, 'no-downloads')),
        backupsDir: Directory(p.join(root.path, 'no-backups')),
      );
      expect(list, isEmpty);
    });

    test('空库候选被标成"关键记录全为 0"，且预览给红色强警告', () async {
      final empty = File(p.join(backups.path, 'fittrack_backup_latest_date.sqlite'));
      await seedDb(empty); // 只建表不写记录
      final list = await BackupCandidateService.listCandidates(
        docsDir: docs,
        downloadDir: downloads,
        backupsDir: backups,
      );
      final candidate = list.single;
      expect(candidate.readable, isTrue);
      expect(candidate.counts!.isEmpty, isTrue);

      final preview = RestorePreview.of(
        candidate: candidate,
        current: const BackupCounts(workouts: 5, bodyMetrics: 3, photos: 2),
      );
      expect(preview.destructive, isTrue);
      expect(preview.hardWarning, isNotNull);
      expect(preview.hardWarning!, contains('清空'));
    });
  });

  // ─────────────────────────────────────────────────────────────
  // 4. 成功路径：旧库保留、照片不动、版本可迁移
  // ─────────────────────────────────────────────────────────────
  group('成功路径', () {
    Future<void> seedPhotos() async {
      await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);
      await File(p.join(photos.path, 'b.jpg')).writeAsBytes([4, 5, 6]);
    }

    test('裸库恢复后：现有照片一张不少，旧库留在 pre-restore，且进入封存', () async {
      await seedPhotos();
      final source = await exported(rows: 4);
      await seedCurrent(rows: 1);

      final result = await restore(source);

      expect(await bodyMetricRows(dbFile), 4, reason: '必须用上用户选的那份');
      expect(await bodyMetricRows(File(result.preRestorePath)), 1,
          reason: '恢复前的数据必须能找回来');
      expect(photos.listSync().whereType<File>().length, 2,
          reason: '裸 .sqlite 没有照片内容，恢复不能把现有照片删掉');
      expect(File(p.join(photos.path, 'a.jpg')).existsSync(), isTrue);
      expect(DatabaseSeal.sealed, isTrue, reason: '必须封存，逼用户重启');
      expect(File(result.preRestoreArchivePath).existsSync(), isTrue,
          reason: '恢复前必须强制打一份完整备份包');
    });

    test('旧版本库（user_version = 22）能恢复，版本号原样保留给下次启动迁移', () async {
      final source = await exported(rows: 3);
      await setUserVersion(source, 22);
      await seedCurrent(rows: 1);

      await restore(source);

      expect(await bodyMetricRows(dbFile), 3);
      expect(await userVersionOf(dbFile), 22,
          reason: '恢复路径不许顺手迁移（那是下次启动的事）');
    });

    test('空库候选在服务层是"允许但先备份"—— 护栏在 UI，数据可退回', () async {
      final source = await exported(rows: 0);
      await seedCurrent(rows: 2);

      final result = await restore(source);

      expect(await bodyMetricRows(dbFile), 0);
      expect(await bodyMetricRows(File(result.preRestorePath)), 2,
          reason: '既然允许覆盖空库，旧数据就必须真的能拿回来');
    });

    test('把"正在用的库"自己当候选恢复 → 不丢数据（只多一次封存）', () async {
      await seedCurrent(rows: 3);
      final source = File(p.join(downloads.path, 'fittrack_backup_self.sqlite'));
      await dbFile.copy(source.path);

      await restore(source);

      expect(await bodyMetricRows(dbFile), 3);
    });
  });
}
