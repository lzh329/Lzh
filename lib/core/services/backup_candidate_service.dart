import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart' show AppDatabase;
import '../database/database_health.dart';
import 'backup_candidate.dart';
import 'restore_service.dart';

// 候选列表的消费方（设置页面板）只需要认识这一个文件
export 'backup_candidate.dart';

/// 列出"可以恢复哪些备份"。
///
/// 存在的理由：旧实现「恢复数据库」只按固定优先级抓 `backups/` 里最新的一份，
/// 既不问用户、也不校验，于是用户刚导出的文件永远不会被用上，而一份"空库时代的
/// 自动备份"却会被自动选中 —— 恢复完就是空库。
///
/// 这个类只回答两个问题：**有哪些候选**、**每份里有多少条记录**。
/// 恢复动作本身仍然交给 [RestoreService]（校验链 + 原子替换）。
class BackupCandidateService {
  BackupCandidateService._();

  /// 「导出数据库」落盘时的前缀（Download 与文档根目录通用）
  static const String exportPrefix = 'fittrack_backup_';

  /// `AutoBackupService.backupNow()` 维护的镜像名。
  ///
  /// 它是"最新那份时间戳备份"的副本，列出来只会让用户在同一份内容里选两次，
  /// 所以跳过。
  static const String latestMirrorName = 'fittrack_backup_latest.sqlite';

  /// 恢复前安全副本前缀（与 `RestoreService.preRestorePrefix` 一致）
  static const String preRestorePrefix = 'pre-restore-';

  /// Android 公共下载目录（导出数据库的落点）
  static const String androidDownloadDir = '/storage/emulated/0/Download';

  /// 枚举全部候选，按时间**倒序**。
  ///
  /// 三个来源任一读不到都只是"少几项"，绝不抛给 UI：
  /// 恢复入口不能因为"某个目录没权限"整条路都打不开。
  ///
  /// [docsDir] / [downloadDir] / [backupsDir] 供单测注入临时目录，
  /// 避免碰真实路径与平台通道。
  static Future<List<BackupCandidate>> listCandidates({
    Directory? docsDir,
    Directory? downloadDir,
    Directory? backupsDir,
  }) async {
    final docs = docsDir ?? await getApplicationDocumentsDirectory();
    final backups = backupsDir ?? Directory(p.join(docs.path, 'backups'));
    final downloads = downloadDir ?? Directory(androidDownloadDir);

    final scratch = await Directory.systemTemp.createTemp('fittrack_probe');
    try {
      // (文件, 来源) —— 顺序无所谓，最后统一按时间倒序
      final found = <MapEntry<File, BackupSourceKind>>[];
      for (final file in await _scan(downloads, _isExportedSqlite)) {
        found.add(MapEntry(file, BackupSourceKind.export));
      }
      // Download 不可写时「导出数据库」会退到文档根目录，这里一并扫，
      // 否则那台手机上的导出文件永远不会出现在候选里
      for (final file in await _scan(docs, _isExportedSqlite)) {
        found.add(MapEntry(file, BackupSourceKind.export));
      }
      for (final file in await _scan(backups, _isExportedSqlite)) {
        found.add(MapEntry(file, BackupSourceKind.autoBackup));
      }
      for (final file in await _scan(backups, _isPreRestoreSqlite)) {
        found.add(MapEntry(file, BackupSourceKind.preRestore));
      }
      // zip 备份包：带照片，清除数据 / 降级页产出的都是这种
      for (final file in await _scan(backups, _isArchive)) {
        found.add(MapEntry(file, BackupSourceKind.archive));
      }

      final candidates = <BackupCandidate>[];
      final seen = <String>{};
      for (final entry in found) {
        if (!seen.add(entry.key.path)) continue; // 同一文件可能被扫两遍
        try {
          candidates.add(await _describe(entry.key, entry.value, scratch));
        } catch (_) {
          // 连 stat 都失败（文件刚被删 / 无权限）→ 当作不存在
        }
      }
      candidates.sort((a, b) {
        final byTime = b.modifiedAt.compareTo(a.modifiedAt);
        return byTime != 0 ? byTime : b.path.compareTo(a.path);
      });
      return candidates;
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 当前库的关键表行数（用于确认弹窗里的对比）。
  ///
  /// 走**已有连接**（调用方传 `databaseProvider` 的实例）：恢复前再开第二个
  /// 连接到同一个文件，会让 drift 的连接池和 WAL/journal 状态更难推理。
  /// 读不出来返回 null（降级态），调用方按"无法对比"处理。
  static Future<BackupCounts?> countsOfDatabase(AppDatabase db) async {
    try {
      return await _countsOf(db);
    } catch (_) {
      return null;
    }
  }

  // ───────────────────── 内部 ─────────────────────

  /// 4 张关键表的行数（表名与 drift 生成的 actualTableName 逐字一致）。
  ///
  /// 缺表按 0 计：这里只负责"摘要好不好看"，"缺表就不能恢复"由
  /// [RestoreService.requiredTables] 在预检里把关。
  static Future<BackupCounts> _countsOf(AppDatabase db) async {
    final existing = await _tableNames(db);
    return BackupCounts(
      workouts: await _countTable(db, 'workouts', existing),
      bodyMetrics: await _countTable(db, 'body_metrics', existing),
      photos: await _countTable(db, 'photos', existing),
      exercises: await _countTable(db, 'exercises', existing),
    );
  }

  static bool _isExportedSqlite(String name) =>
      name.startsWith(exportPrefix) &&
      name.endsWith('.sqlite') &&
      name != latestMirrorName;

  static bool _isPreRestoreSqlite(String name) =>
      name.startsWith(preRestorePrefix) && name.endsWith('.sqlite');

  static bool _isArchive(String name) => name.endsWith('.zip');

  static Future<List<File>> _scan(
    Directory dir,
    bool Function(String name) accept,
  ) async {
    try {
      if (!await dir.exists()) return const [];
      final files = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        if (accept(p.basename(entity.path))) files.add(entity);
      }
      return files;
    } catch (_) {
      // 分区没挂载 / 权限不足：按"这个来源没有备份"处理
      return const [];
    }
  }

  static Future<BackupCandidate> _describe(
    File file,
    BackupSourceKind kind,
    Directory scratch,
  ) async {
    final stat = await file.stat();
    final probe = kind == BackupSourceKind.archive
        ? await _probeArchive(file)
        : await _probeSqlite(file, scratch);
    return BackupCandidate(
      path: file.path,
      kind: kind,
      modifiedAt: stat.modified,
      sizeBytes: stat.size,
      counts: probe.counts,
      userVersion: probe.userVersion,
      readable: probe.readable,
    );
  }

  /// 裸 sqlite 的探测。
  ///
  /// **先复制到临时目录再打开**：drift 的 `NativeDatabase` 没有 readOnly 参数，
  /// 直接打开候选文件会在它旁边留下 `-journal` / `-wal` 旁文件，甚至写回主文件。
  /// 恢复流程去改用户手上的备份原件，比"恢复错了"更难解释 —— 一份一百多 KB
  /// 的副本换"原件一个字节都不动"，值得。
  static Future<_Probe> _probeSqlite(File source, Directory scratch) async {
    File? copy;
    AppDatabase? db;
    try {
      final userVersion = await DatabaseFileHealth.readUserVersion(source);
      if (userVersion == null) {
        // 文件头都读不出 → 不是合法 sqlite，连打开都省了
        return const _Probe.unreadable();
      }
      copy = File(p.join(
        scratch.path,
        'probe_${DateTime.now().microsecondsSinceEpoch}_${p.basename(source.path)}',
      ));
      await source.copy(copy.path);
      db = AppDatabase.withExecutor(
        NativeDatabase(copy, enableMigrations: false),
      );
      return _Probe(
        counts: await _countsOf(db),
        userVersion: userVersion,
        readable: true,
      );    } catch (_) {
      return const _Probe.unreadable();
    } finally {
      try {
        await db?.close();
      } catch (_) {}
      if (copy != null) {
        for (final path in [copy.path, '${copy.path}-journal']) {
          try {
            final f = File(path);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
    }
  }

  /// zip 备份包的探测：读 manifest 里的行数与版本，不整包解压。
  ///
  /// archive 3.x 没有流式解码（`decodeBuffer` 会把**压缩数据**整包读进内存），
  /// 所以超过 [maxArchiveProbeBytes] 的包不解析：为了显示一行行数去吃掉几十 MB
  /// 内存不值当。这时 `counts` 留 null，UI 如实说"无法统计"，
  /// 真正的行数校验仍由恢复流程里的 manifest 对账完成。
  static const int maxArchiveProbeBytes = 8 * 1024 * 1024;

  static Future<_Probe> _probeArchive(File file) async {
    InputFileStream? stream;
    try {
      if (await file.length() > maxArchiveProbeBytes) {
        return const _Probe.unknown();
      }
      stream = InputFileStream(file.path);
      final archive = ZipDecoder().decodeBuffer(stream);
      var hasDb = false;
      Map<String, dynamic>? manifest;
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        if (p.basename(entry.name) == RestoreService.dbFileName) hasDb = true;
        if (entry.name == 'manifest.json' && manifest == null) {
          final content = entry.content;
          if (content is List<int>) {
            final decoded = jsonDecode(utf8.decode(content));
            if (decoded is Map<String, dynamic>) manifest = decoded;
          }
        }
      }
      if (!hasDb) return const _Probe.unreadable();
      return _Probe(
        counts: _countsFromManifest(manifest),
        userVersion: _asInt(manifest?['schemaVersion']),
        readable: true,
      );
    } catch (_) {
      return const _Probe.unreadable();
    } finally {
      try {
        stream?.closeSync();
      } catch (_) {}
    }
  }

  static BackupCounts? _countsFromManifest(Map<String, dynamic>? manifest) {
    final raw = manifest?['tableCounts'];
    if (raw is! Map) return null;
    return BackupCounts(
      workouts: _asInt(raw['workouts']) ?? 0,
      bodyMetrics: _asInt(raw['body_metrics']) ?? 0,
      photos: _asInt(raw['photos']) ?? _asInt(manifest?['photoCount']) ?? 0,
      exercises: _asInt(raw['exercises']) ?? 0,
    );
  }

  static Future<Set<String>> _tableNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  static Future<int> _countTable(
    AppDatabase db,
    String table,
    Set<String> existing,
  ) async {
    if (!existing.contains(table)) return 0;
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM "$table"')
        .getSingle();
    return (row.data['c'] as num).toInt();
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// 探测结果（内部用；`counts == null` 表示统计不出来）
@immutable
class _Probe {
  final BackupCounts? counts;
  final int? userVersion;
  final bool readable;

  const _Probe({
    required this.counts,
    required this.userVersion,
    required this.readable,
  });

  const _Probe.unreadable()
      : counts = null,
        userVersion = null,
        readable = false;

  /// 能读但**不统计**（超大 zip / manifest 缺行数）：可恢复，行数未知
  const _Probe.unknown()
      : counts = null,
        userVersion = null,
        readable = true;
}
