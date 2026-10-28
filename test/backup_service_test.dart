import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/backup_service.dart';

/// 造一个真实的 v21 库（可选：再造几张照片）
Future<void> seedDatabase(File dbFile) async {
  final db = AppDatabase.withExecutor(NativeDatabase(dbFile));
  await db.customSelect('SELECT 1').get();
  await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 3, 4),
        weightKg: 68.5,
      ));
  await db.close();
}

Archive readArchive(File zip) =>
    ZipDecoder().decodeBytes(zip.readAsBytesSync());

void main() {
  group('纯逻辑：journalMode 判定（文件头 offset 18/19）', () {
    Uint8List header({int write = 1, int read = 1}) {
      final bytes = Uint8List(64);
      bytes[18] = write;
      bytes[19] = read;
      return bytes;
    }

    test('write/read = 1 → delete（rollback journal）', () {
      expect(BackupService.journalModeFromHeader(header()), 'delete');
    });

    test('任一侧 = 2 → wal', () {
      expect(
        BackupService.journalModeFromHeader(header(write: 2, read: 2)),
        'wal',
      );
      expect(
        BackupService.journalModeFromHeader(header(write: 1, read: 2)),
        'wal',
      );
    });

    test('读不出 / 太短 → unknown（不猜）', () {
      expect(BackupService.journalModeFromHeader(null), 'unknown');
      expect(
        BackupService.journalModeFromHeader(Uint8List.fromList([1, 2, 3])),
        'unknown',
      );
    });
  });

  group('纯逻辑：文件名与 sidecar 清单', () {
    test('archiveFileName 带日期，扩展名是 zip（不是裸 sqlite）', () {
      final name = BackupService.archiveFileName(DateTime(2025, 3, 4, 5, 6, 7));
      expect(name, 'fittrack_backup_20250304-050607.zip');
    });

    test('sidecarPathsFor 覆盖 -wal / -shm / -journal 三种日志', () {
      final paths = BackupService.sidecarPathsFor('/data/fittrack.sqlite');
      expect(paths, [
        '/data/fittrack.sqlite-wal',
        '/data/fittrack.sqlite-shm',
        '/data/fittrack.sqlite-journal',
      ]);
    });
  });

  group('真实打包', () {
    late Directory root;
    late File dbFile;
    late Directory photos;
    late Directory out;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fittrack_backup');
      dbFile = File(p.join(root.path, 'fittrack.sqlite'));
      photos = Directory(p.join(root.path, 'photos'));
      out = Directory(p.join(root.path, 'out'));
      await photos.create(recursive: true);
      await out.create(recursive: true);
    });

    tearDown(() async {
      try {
        if (await root.exists()) await root.delete(recursive: true);
      } catch (_) {}
    });

    test('在线路径：VACUUM INTO 快照 + 照片 + manifest 齐备', () async {
      await seedDatabase(dbFile);
      await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);
      await File(p.join(photos.path, 'b.jpg')).writeAsBytes([4, 5]);

      final result = await BackupService.createArchive(
        dbPath: dbFile.path,
        photosDir: photos,
        outputDir: out,
        now: DateTime(2025, 3, 4, 5, 6, 7),
        tableCounts: {'body_metrics': 1},
      );

      expect(result.dbSource, 'snapshot');
      expect(result.photoCount, 2);
      expect(result.dbFiles, ['fittrack.sqlite']);
      expect(result.journalMode, anyOf('delete', 'wal', 'unknown'));
      expect(result.dbSha256.length, 64);

      final archive = readArchive(File(result.path));
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('fittrack.sqlite'));
      expect(names, contains('photos/a.jpg'));
      expect(names, contains('photos/b.jpg'));
      expect(names, contains('manifest.json'));

      final manifest = jsonDecode(utf8.decode(
        archive.files.firstWhere((f) => f.name == 'manifest.json').content
            as List<int>,
      )) as Map<String, dynamic>;
      expect(manifest['archiveVersion'], 2);
      expect(manifest['journalMode'], isA<String>());
      expect(manifest['photoCount'], 2);
      expect(manifest['dbFiles'], ['fittrack.sqlite']);
      expect(manifest['dbSha256'], result.dbSha256);
      expect(manifest['tableCounts'], {'body_metrics': 1});
      expect(manifest['schemaVersion'], kSchemaVersion);
    });

    test('包里的库是 VACUUM 过的完整库：能读回原数据', () async {
      await seedDatabase(dbFile);
      final result = await BackupService.createArchive(
        dbPath: dbFile.path,
        photosDir: photos,
        outputDir: out,
      );

      final archive = readArchive(File(result.path));
      final extracted = File(p.join(root.path, 'extracted.sqlite'));
      await extracted.writeAsBytes(
        archive.files.firstWhere((f) => f.name == 'fittrack.sqlite').content
            as List<int>,
      );

      final db = AppDatabase.withExecutor(NativeDatabase(extracted));
      final metrics = await db.select(db.bodyMetrics).get();
      expect(metrics.single.weightKg, 68.5);
      await db.close();
    });

    test('降级路径（allowOpenDatabase: false）：整组 raw copy，tableCounts 留空', () async {
      await seedDatabase(dbFile);
      // 造一个 -wal 残留，验证它会跟着一起进包
      await File('${dbFile.path}-wal').writeAsBytes([9, 9, 9]);

      final result = await BackupService.createArchive(
        dbPath: dbFile.path,
        photosDir: photos,
        outputDir: out,
        allowOpenDatabase: false,
      );

      expect(result.dbSource, 'rawCopy');
      expect(result.dbFiles,
          containsAll(['fittrack.sqlite', 'fittrack.sqlite-wal']));

      final archive = readArchive(File(result.path));
      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('fittrack.sqlite-wal'),
          reason: '-wal 里有已提交未 checkpoint 的页，只拷主文件会丢最近写入');

      final manifest = jsonDecode(utf8.decode(
        archive.files.firstWhere((f) => f.name == 'manifest.json').content
            as List<int>,
      )) as Map<String, dynamic>;
      expect(manifest.containsKey('tableCounts'), isFalse,
          reason: '打不开库就没法统计行数，该字段留空 → 恢复侧按"缺失就警告放行"处理');
    });

    test('库损坏时 VACUUM 失败自动退到 raw copy（不让用户自己判断）', () async {
      await dbFile.writeAsBytes(List.filled(200, 65)); // 不是合法 sqlite
      await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1]);

      final result = await BackupService.createArchive(
        dbPath: dbFile.path,
        photosDir: photos,
        outputDir: out,
      );

      expect(result.dbSource, 'rawCopy', reason: '库结构读不出来时级联到文件搬运，而不是直接失败');
      expect(File(result.path).existsSync(), isTrue);
    });

    test('数据库文件不存在时抛异常（不静默产出一个空包）', () async {
      await expectLater(
        BackupService.createArchive(
          dbPath: p.join(root.path, 'missing.sqlite'),
          photosDir: photos,
          outputDir: out,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('没有 photos 目录也能打包（photoCount == 0）', () async {
      await seedDatabase(dbFile);
      final result = await BackupService.createArchive(
        dbPath: dbFile.path,
        photosDir: Directory(p.join(root.path, 'nope')),
        outputDir: out,
      );
      expect(result.photoCount, 0);
      expect(File(result.path).existsSync(), isTrue);
    });
  });
}
