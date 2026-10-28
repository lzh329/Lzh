import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart' show AppDatabase, kSchemaVersion;

/// 备份包产物信息（同时用于 manifest 与日志/提示）。
class BackupArchive {
  final String path;

  /// 数据库是怎么进包的：
  /// - `snapshot`：`VACUUM INTO` 产出的干净快照（库结构可读时的首选）
  /// - `rawCopy`：整组文件原样复制（降级态 / VACUUM 失败时的兜底）
  final String dbSource;

  /// 包内数据库相关文件的文件名清单（恢复时按它逐个放回原位）
  final List<String> dbFiles;

  final int photoCount;
  final String journalMode;
  final String dbSha256;

  const BackupArchive({
    required this.path,
    required this.dbSource,
    required this.dbFiles,
    required this.photoCount,
    required this.journalMode,
    required this.dbSha256,
  });
}

/// 备份打包服务：**一处实现，两处使用**（降级页「先存一份数据」+ 每周自动备份）。
///
/// 为什么是 zip 而不是只 copy `.sqlite`：
/// 照片是 `documents/photos/` 下的独立文件，**不在库里**。只给 db，用户在最需要
/// 它的时候会少一半数据 —— 这和"只导两张 CSV"是同一个错误换了个位置。
///
/// ⚠️ 写在这里、半年后仍然成立的前提：
/// 本 App **从未开启 WAL**（走 DELETE journal，数据全在主文件）。将来任何人把
/// `journal_mode` 改成 WAL，`createArchive()` 必须先在**主连接上做一次
/// checkpoint**，否则备份会缺最近几次写入 —— 而 zip 看起来是完整的，属于
/// 最难发现的静默错误。manifest 里的 `journalMode` 就是给恢复侧留的判据。
class BackupService {
  BackupService._();

  /// manifest 结构版本。2 = 含 journalMode / dbFiles / dbSha256 / photoCount
  static const int archiveVersion = 2;

  /// SQLite 文件头里 write/read version 的偏移（1 = rollback journal, 2 = WAL）
  static const int writeVersionOffset = 18;
  static const int readVersionOffset = 19;

  static String stamp(DateTime now) =>
      DateFormat('yyyyMMdd-HHmmss').format(now);

  static String archiveFileName(DateTime now) =>
      'fittrack_backup_${stamp(now)}.zip';

  /// 从文件头判断日志模式（纯函数，便于单测）。
  ///
  /// 1 = rollback journal（对应 `journal_mode=DELETE`），2 = WAL，
  /// 其他/读不出返回 `unknown`。
  static String journalModeFromHeader(Uint8List? header) {
    if (header == null || header.length <= readVersionOffset) return 'unknown';
    final write = header[writeVersionOffset];
    final read = header[readVersionOffset];
    if (write == 2 || read == 2) return 'wal';
    if (write == 1 || read == 1) return 'delete';
    return 'unknown';
  }

  /// 与主库配套的日志文件（**按存在与否**带进包）。
  ///
  /// 只拷主文件 = 丢最近写入（`-wal` 里是已提交但未 checkpoint 的页）。
  /// 只拷主文件却留着 `-journal` 更糟：恢复时会被当成热日志，把正常数据回滚掉。
  static List<String> sidecarPathsFor(String dbPath) => [
        '$dbPath-wal',
        '$dbPath-shm',
        '$dbPath-journal',
      ];

  /// 生成备份包。
  ///
  /// [tableCounts] 由调用方（能打开库时）提供；**降级态传 null**
  /// —— 打不开库就没法统计行数，manifest 里该字段留空，恢复侧按
  /// "字段缺失 → 警告放行"处理。
  static Future<BackupArchive> createArchive({
    String? dbPath,
    Directory? photosDir,
    Directory? outputDir,
    DateTime? now,
    Map<String, int>? tableCounts,
    bool allowOpenDatabase = true,
  }) async {
    final at = now ?? DateTime.now();
    // 惰性解析文档目录：单测会显式传入全部路径，此时不该碰平台通道
    final dbFile = File(
      dbPath ??
          p.join(await getApplicationDocumentsDirectory().then((d) => d.path),
              'fittrack.sqlite'),
    );
    if (!await dbFile.exists()) {
      throw StateError('数据库文件不存在，无法备份');
    }
    final photos = photosDir ??
        Directory(p.join(
          await getApplicationDocumentsDirectory().then((d) => d.path),
          'photos',
        ));
    final out = outputDir ?? await _defaultOutputDir();

    final header = await _readHeader(dbFile);
    final journalMode = journalModeFromHeader(header);

    final archive = Archive();
    final staging = await Directory.systemTemp.createTemp('fittrack_archive');
    var dbSource = 'rawCopy';
    final dbFiles = <String>[];

    try {
      // ── 1) 首选：VACUUM INTO 干净快照（库结构可读时的最佳结果）──
      var snapshotted = false;
      if (allowOpenDatabase) {
        final snapshotPath = p.join(staging.path, 'fittrack.sqlite');
        snapshotted = await _trySnapshot(dbFile, snapshotPath);
        if (snapshotted) {
          dbSource = 'snapshot';
          dbFiles.add('fittrack.sqlite');
          await _addFileToArchive(
              archive, File(snapshotPath), 'fittrack.sqlite');
        }
      }

      // ── 2) 兜底：整组文件 raw copy（db + 存在才带的 -wal/-shm/-journal）──
      //
      // 降级态走这条：此时没有写入者，原样搬是安全的。
      // 不做 VACUUM 的好处是：即使库损坏也能把"现场"带出去排查。
      if (!snapshotted) {
        final groupDir = Directory(p.join(staging.path, 'raw'));
        await groupDir.create(recursive: true);
        for (final source in [dbFile.path, ...sidecarPathsFor(dbFile.path)]) {
          final file = File(source);
          if (!await file.exists()) continue;
          final name = p.basename(source);
          final copy = File(p.join(groupDir.path, name));
          await file.copy(copy.path);
          dbFiles.add(name);
          await _addFileToArchive(archive, copy, name);
        }
      }

      // ── 3) 照片（不在库里，必须单独打包）──
      var photoCount = 0;
      if (await photos.exists()) {
        await for (final entity in photos.list(followLinks: false)) {
          if (entity is! File) continue;
          await _addFileToArchive(
              archive, entity, 'photos/${p.basename(entity.path)}');
          photoCount++;
        }
      }

      // ── 4) manifest ──
      final dbHash = await _sha256(File(
        snapshotted
            ? p.join(staging.path, 'fittrack.sqlite')
            : p.join(staging.path, 'raw', 'fittrack.sqlite'),
      ));
      final manifest = <String, dynamic>{
        'archiveVersion': archiveVersion,
        'createdAt': at.toIso8601String(),
        'schemaVersion': kSchemaVersion,
        'journalMode': journalMode,
        'dbSource': dbSource,
        'dbFiles': dbFiles,
        'photoCount': photoCount,
        'dbSha256': dbHash,
        // 打不开库时留空：恢复侧按「字段缺失 → 警告放行」处理
        if (tableCounts != null) 'tableCounts': tableCounts,
      };
      final manifestBytes = Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)));
      archive.addFile(
          ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // ── 5) 写 zip ──
      await out.create(recursive: true);
      final zipFile = File(p.join(out.path, archiveFileName(at)));
      final bytes = ZipEncoder().encode(archive) ?? const <int>[];
      await zipFile.writeAsBytes(bytes, flush: true);

      return BackupArchive(
        path: zipFile.path,
        dbSource: dbSource,
        dbFiles: dbFiles,
        photoCount: photoCount,
        journalMode: journalMode,
        dbSha256: dbHash,
      );
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {
        // 临时目录清不掉不影响备份结果
      }
    }
  }

  static Future<Directory> _defaultOutputDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 用 `VACUUM INTO` 产出干净快照（不含 `-wal` / `-journal` 的中间态）。
  ///
  /// 用 `enableMigrations: false` 打开：**绝不**在备份路径上触发迁移 ——
  /// 备份是只读意图，顺手升级库会变成"点备份导致数据被改"。
  /// 打不开（损坏 / 权限）就返回 false，由调用方退到整组 raw copy。
  static Future<bool> _trySnapshot(File source, String targetPath) async {
    final target = File(targetPath);
    if (await target.exists()) await target.delete();
    final db = AppDatabase.withExecutor(
      NativeDatabase(source, enableMigrations: false),
    );
    try {
      await db.customStatement(
        "VACUUM INTO '${targetPath.replaceAll("'", "''")}'",
      );
      return await target.exists();
    } catch (_) {
      return false;
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  static Future<Uint8List?> _readHeader(File file) async {
    try {
      final handle = await file.open();
      try {
        return Uint8List.fromList(await handle.read(64));
      } finally {
        await handle.close();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<String> _sha256(File file) async {
    try {
      if (!await file.exists()) return '';
      final digest = sha256.convert(await file.readAsBytes());
      return digest.toString();
    } catch (_) {
      return '';
    }
  }

  static Future<void> _addFileToArchive(
    Archive archive,
    File file,
    String name,
  ) async {
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(name, bytes.length, Uint8List.fromList(bytes)));
  }
}
