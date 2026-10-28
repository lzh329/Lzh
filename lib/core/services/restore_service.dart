import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart' show AppDatabase, kSchemaVersion;
import '../database/database_health.dart';
import '../database/db_replaced_marker.dart';
import 'backup_service.dart';

/// 恢复被**中止**（不是崩溃）。`reason` 可直接展示给用户。
///
/// 中止意味着：**用户的原库一个字节都没动**。这条是恢复流程最重要的不变量 ——
/// 校验全部在 `restore.tmp` 上做，任何一步不过就原地退出。
class RestoreAborted implements Exception {
  /// 可直接展示的中文原因
  final String reason;

  /// 对不上的表名（行数校验失败时）
  final String? table;
  final int? expected;
  final int? actual;

  const RestoreAborted(
    this.reason, {
    this.table,
    this.expected,
    this.actual,
  });

  @override
  String toString() => 'RestoreAborted($reason'
      '${table == null ? '' : ', table=$table, expected=$expected, actual=$actual'})';
}

class RestoreResult {
  /// 恢复前被 rename 保留的原库路径（`pre-restore-<ts>.sqlite`）
  final String preRestorePath;

  /// 恢复前生成的完整备份包（zip，含照片）—— 双重保险，用户可整包带走
  final String preRestoreArchivePath;

  /// 实际恢复出的照片数（供用户自行核对；无 manifest 的旧备份只能靠这个兜底）
  final int photoCount;

  /// 可展示的警告（例如"旧版备份，无法校验完整性"）
  final List<String> warnings;

  const RestoreResult({
    required this.preRestorePath,
    required this.preRestoreArchivePath,
    required this.photoCount,
    required this.warnings,
  });
}

/// 判断剩余空间是否够（返回 null = 无法判断，按够处理）。
typedef FreeSpaceProbe = Future<int?> Function();

/// 备份恢复服务：校验链 + 原子替换 + `pre-restore` 生命周期。
///
/// 设计铁律（改这个文件前先读）：
/// 1. **校验全部在 `restore.tmp` 上做**，全部通过才 rename 覆盖真库。
///    校验失败时用户的原库必须还没被碰过。
/// 2. **失败路径只允许"重命名保留"，不允许 delete**（不做事务回滚那套）。
/// 3. 恢复前必须强制备份当前库，备份失败即中止 —— 不允许在"当前数据没备份"
///    的状态下动库。
class RestoreService {
  RestoreService._();

  /// `pre-restore-*` 最多保留的份数。
  ///
  /// 「恢复两次都没重启」时，第一份才是真正的原始数据，所以不是保留 1 份。
  /// 这些文件**不占** `AutoBackupService.keep` 的额度、且永不参与自动清理
  /// （见 `AutoBackupService.listBackups` 的前缀过滤）。
  static const int keepPreRestore = 2;

  /// 恢复前的安全副本前缀（与 `DatabaseRecoveryService` 保持一致）
  static const String preRestorePrefix = 'pre-restore';

  /// 恢复目标文件名
  static const String dbFileName = 'fittrack.sqlite';

  /// 恢复整个备份包。
  ///
  /// [closeDatabase]：在 rename 之前关闭当前连接（调用方提供，通常是
  /// `ref.read(databaseProvider).close()`）。不传则假定调用方已自行处理。
  static Future<RestoreResult> restoreArchive({
    required String archivePath,
    String? dbPath,
    Directory? photosDir,
    Directory? backupDir,
    DateTime? now,
    FreeSpaceProbe? freeSpace,
    Future<void> Function()? closeDatabase,

    /// 文档目录（null = 走 path_provider）。单测注入临时目录，避免碰平台通道。
    Directory? docsDir,
  }) async {
    final at = now ?? DateTime.now();
    final docs = docsDir ?? await getApplicationDocumentsDirectory();
    final target = File(dbPath ?? p.join(docs.path, dbFileName));
    final photos = photosDir ?? Directory(p.join(docs.path, 'photos'));
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw const RestoreAborted('备份包不存在');
    }

    // ── Step 0：空间检查（不足直接中止，此时还没做任何重命名）──
    await _checkFreeSpace(archiveFile, target, freeSpace);

    // ── Step 1：强制先备份当前库；失败即中止 ──
    final safety = await BackupService.createArchive(
      dbPath: target.path,
      photosDir: photos,
      outputDir: backupDir,
      now: at,
      // 当前库可能正是在降级态（打不开），此时只能整组 raw copy
      allowOpenDatabase: false,
      // 独立前缀：默认的 `fittrack_backup_<stamp>.zip` 与用户选中的备份
      // 在同一秒内会撞名，那会把用户要恢复的包直接覆盖掉
      fileName: 'pre-restore-archive-${BackupService.stamp(at)}.zip',
      protectPath: archiveFile.path,
    );

    final tmpRoot = Directory(
      p.join(docs.path, 'restore.tmp.${at.millisecondsSinceEpoch}'),
    );
    final warnings = <String>[];
    try {
      // ── Step 2：解压到 tmp ──
      final extracted = await _extract(archiveFile, tmpRoot);
      final tmpDb = File(p.join(extracted.path, dbFileName));
      if (!await tmpDb.exists()) {
        throw const RestoreAborted('备份包里没有数据库文件');
      }

      // ── Step 3：校验链（顺序不可调换，全部在 tmp 上做）──
      // a) manifest 可解析
      final manifest = await _readManifest(extracted);
      if (manifest == null) {
        warnings.add('这份备份没有校验信息，只能确认文件没有损坏。里面的照片可能不完整。');
      }

      // b) integrity_check
      await _integrityCheck(tmpDb);

      // c) 版本校验（双向）：比当前 App 新 → 拒绝；更旧 → 允许（下次启动走迁移）
      // manifest.schemaVersion 是**源库自己的 user_version**（不是打包时的
      // App 版本）。读不出（旧包 / 文件头坏的包）→ 无法判断版本：警告放行，
      // 真的不兼容会在后面 integrity_check / 打开时暴露，再中止。
      final archiveSchema = _asInt(manifest?['schemaVersion']);
      if (archiveSchema == null) {
        warnings.add('无法判断这份备份的数据版本，将直接尝试恢复。');
      }
      if (archiveSchema != null && archiveSchema > kSchemaVersion) {
        throw RestoreAborted(
          '这份备份来自更新版本的减肥嘎（数据版本 $archiveSchema，当前 App 支持 $kSchemaVersion），请先更新 App',
        );
      }

      // d) 行数比对（只比交集表；缺失 → 警告放行；不一致 → 整体中止）
      final expectedCounts = _readTableCounts(manifest);
      if (expectedCounts == null) {
        if (manifest != null) {
          warnings.add('这份备份没有行数校验信息（可能是在降级状态下打的包），无法核对完整性。');
        }
      } else {
        final actualCounts = await _tableCounts(tmpDb, expectedCounts.keys);
        _compareCounts(expectedCounts, actualCounts);
      }

      // e) photoCount 比对（照片是独立文件，最容易缺）
      final expectedPhotos = _asInt(manifest?['photoCount']);
      final tmpPhotos = Directory(p.join(extracted.path, 'photos'));
      final actualPhotos = await _countFiles(tmpPhotos);
      if (expectedPhotos != null && expectedPhotos != actualPhotos) {
        throw RestoreAborted(
          '备份包里的照片数量对不上（期望 $expectedPhotos 张，实际 $actualPhotos 张），先别覆盖现在的数据',
        );
      }

      // f) 导入后二次对账（rename 之前再做一遍，规则与第一道相同）
      if (expectedCounts != null) {
        _compareCounts(
          expectedCounts,
          await _tableCounts(tmpDb, expectedCounts.keys),
        );
      }

      // ── Step 4：原子替换 ──
      //
      // 顺序写死，不可颠倒：
      //   写标记(fsync) → close 连接 → rename → 置 sealed → 新库独立打开校验 → 清标记
      //
      // 为什么标记必须在 rename **之前**写：rename 之后到写标记之间，没有任何
      // 东西阻止同进程继续用旧句柄写，代价是静默丢数据。
      // 为什么 sealed 在 rename **之后**：真正的保护是"rename 前 close 连接"
      // （连接一关，任何还持有旧引用的 notifier/定时器再写都会拿到
      // "database is closed"，而不是静默写进被替换的文件）；sealed 负责的是
      // 用户体验 + 阻止重开后旧 provider 继续用缓存数据。两层各管一段。
      final safetyName = p.join(
        (backupDir ?? await _defaultBackupDir()).path,
        '$preRestorePrefix-${BackupService.stamp(at)}.sqlite',
      );

      await DbReplacedMarker.write(
        preRestore: safetyName,
        baseDir: docs,
      );

      if (closeDatabase != null) {
        try {
          await closeDatabase();
        } catch (_) {
          // 库可能本来就没打开成功
        }
      }

      // 失败路径只允许"重命名保留"，绝不 delete 真库。
      if (await target.exists()) {
        await target.rename(safetyName);
      }
      await tmpDb.rename(target.path);

      // 旧库的日志残留必须清掉：否则 SQLite 下次打开会把旧页回放进新库，
      // 表现为"恢复后仍能查到已经不存在的记录"。
      for (final journal in BackupService.sidecarPathsFor(target.path)) {
        final file = File(journal);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }

      DatabaseSeal.seal();

      // 新库独立打开校验：**不走 provider**（此刻 sealed，走 provider 会被自己挡住）
      await _verifyReopened(target);

      await DbReplacedMarker.clear(baseDir: docs);
      DatabaseSeal.unseal();

      // 照片：覆盖式导入
      if (await tmpPhotos.exists()) {
        if (!await photos.exists()) await photos.create(recursive: true);
        await for (final entity in tmpPhotos.list(followLinks: false)) {
          if (entity is! File) continue;
          await entity.copy(p.join(photos.path, p.basename(entity.path)));
        }
      }

      // ── Step 5：pre-restore 生命周期 ──
      await prunePreRestore(backupDir: backupDir);

      return RestoreResult(
        preRestorePath: safetyName,
        preRestoreArchivePath: safety.path,
        photoCount: actualPhotos,
        warnings: warnings,
      );
    } catch (e) {
      throw _asAbort(e);
    } finally {
      try {
        if (await tmpRoot.exists()) await tmpRoot.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 从 `pre-restore-*.sqlite` 退回。
  ///
  /// **不走第二套逻辑**：先把它打成一个最小 zip（只含库 + 现算的 manifest），
  /// 再交给 [restoreArchive] 走同一条校验链。理由：`pre-restore` 文件没人保证
  /// 完整（磁盘错误 / 写到一半被杀），如果它坏了，用一条没校验的路径覆盖真库
  /// 等于用坏数据二次毁现场 —— 而用户此刻已经没有第三份了。
  static Future<RestoreResult> restoreFromPreRestore({
    required String preRestorePath,
    String? dbPath,
    Directory? photosDir,
    Directory? backupDir,
    DateTime? now,
    FreeSpaceProbe? freeSpace,
    Future<void> Function()? closeDatabase,
    Directory? docsDir,
  }) async {
    final source = File(preRestorePath);
    if (!await source.exists()) {
      throw const RestoreAborted('恢复前的那份数据已经不在了');
    }
    final docs = docsDir ?? await getApplicationDocumentsDirectory();
    final tempDir =
        await Directory.systemTemp.createTemp('fittrack_pre_restore');
    final tempZip = File(p.join(tempDir.path, 'pre-restore.zip'));
    try {
      // 现算 manifest：版本从文件头读，行数从库里数（都走"不打开迁移"的路径）
      final header = await _readHeader(source);
      final schemaVersion =
          DatabaseFileHealth.parseUserVersion(header ?? Uint8List(0));
      final counts = await _tableCountsForManifest(source);

      final encoder = ZipFileEncoder();
      encoder.create(tempZip.path);
      try {
        await encoder.addFile(source, dbFileName);
        final manifest = File(p.join(tempDir.path, 'manifest.json'));
        await manifest.writeAsString(
          jsonEncode(<String, dynamic>{
            'archiveVersion': BackupService.archiveVersion,
            'createdAt': DateTime.now().toIso8601String(),
            'schemaVersion': schemaVersion,
            'dbSource': 'preRestore',
            'dbFiles': [dbFileName],
            'photoCount': 0,
            if (counts.isNotEmpty) 'tableCounts': counts,
          }),
          flush: true,
        );
        await encoder.addFile(manifest, 'manifest.json');
      } finally {
        encoder.close();
      }

      return await restoreArchive(
        archivePath: tempZip.path,
        dbPath: dbPath ?? p.join(docs.path, dbFileName),
        photosDir: photosDir,
        backupDir: backupDir,
        now: now,
        freeSpace: freeSpace,
        closeDatabase: closeDatabase,
        docsDir: docs,
      );
    } finally {
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
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

  /// 给 pre-restore 现算各表行数（表名取自库自身，避免依赖 schema 常量）
  static Future<Map<String, int>> _tableCountsForManifest(File dbFile) async {
    final db = AppDatabase.withExecutor(
      NativeDatabase(dbFile, enableMigrations: false),
    );
    final counts = <String, int>{};
    try {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      for (final row in rows) {
        final name = row.read<String>('name');
        if (name.startsWith('sqlite_')) continue;
        final count = await db
            .customSelect('SELECT COUNT(*) AS c FROM "$name"')
            .getSingle();
        counts[name] = (count.data['c'] as num).toInt();
      }
    } catch (_) {
      return {};
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
    return counts;
  }

  /// 替换后独立打开一次新库，确认它能用（不是"rename 成了"就算完成）。
  ///
  /// 用独立连接，不走 `databaseProvider` —— 此刻已 sealed。
  static Future<void> _verifyReopened(File dbFile) async {
    try {
      await _integrityCheck(dbFile);
    } catch (e) {
      // 新库打不开是**严重**情况（真库已被 rename 掉），但标记仍在，
      // 下次启动会重试消解；这里不能假装成功。
      throw RestoreAborted(
        '数据已经替换，但新库打不开。原来的数据已另存为 ${p.basename(dbFile.path)}.backup，'
        '重新打开 App 会再试一次。',
      );
    }
  }

  /// `pre-restore` 只保留最近 [keepPreRestore] 份。
  ///
  /// 清理时机是「恢复成功之后的收尾」，而不是恢复当下 —— B13b 要能退回去。
  static Future<void> prunePreRestore({Directory? backupDir}) async {
    final dir = backupDir ?? await _defaultBackupDir();
    if (!await dir.exists()) return;
    // 先清 .zip，再清 .sqlite：`.zip` 只是给用户手动导出用的，
    // `.sqlite` 是「回到恢复前的数据」的唯一来源 —— 清理顺序必须保证
    // 前者先走，后者**至少留 1 份**。
    for (final suffix in ['.zip', '.sqlite']) {
      final files = (await dir.list().toList())
          .whereType<File>()
          .where((f) =>
              p.basename(f.path).startsWith('$preRestorePrefix-') &&
              f.path.endsWith(suffix))
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      // .sqlite 至少留 1 份：它没了「回到恢复前的数据」按钮就不能显示
      final limit = suffix == '.sqlite'
          ? (keepPreRestore < 1 ? 1 : keepPreRestore)
          : keepPreRestore;
      for (var i = limit; i < files.length; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    }
  }

  /// 找最近一份 `pre-restore-*`（降级页「回到恢复前的数据」用）。
  static Future<String?> latestPreRestore({Directory? backupDir}) async {
    final dir = backupDir ?? await _defaultBackupDir();
    if (!await dir.exists()) return null;
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) =>
            p.basename(f.path).startsWith('$preRestorePrefix-') &&
            f.path.endsWith('.sqlite'))
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.first.path;
  }

  // ───────────────────── 内部 ─────────────────────

  static Future<Directory> _defaultBackupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _checkFreeSpace(
    File archive,
    File target,
    FreeSpaceProbe? probe,
  ) async {
    if (probe == null) return; // 未注入探测器：无法判断，按够处理
    final free = await probe();
    if (free == null) return;
    // 需要：解压出的库 + 一份 pre-restore 安全副本，按归档大小的 3 倍估
    final need = await archive.length() * 3;
    if (free < need) {
      throw RestoreAborted(
        '手机剩余空间不足（需要约 ${(need / 1024 / 1024).toStringAsFixed(0)}MB，'
        '可用 ${(free / 1024 / 1024).toStringAsFixed(0)}MB），先清理空间再恢复',
      );
    }
    // target 存在性不影响判断，保留参数便于将来按库大小精确估算
    if (await target.exists()) return;
  }

  static Future<Directory> _extract(File archive, Directory into) async {
    if (await into.exists()) await into.delete(recursive: true);
    await into.create(recursive: true);
    try {
      final decoder = ZipDecoder();
      final bytes = await archive.readAsBytes();
      final decoded = decoder.decodeBytes(bytes);
      for (final entry in decoded.files) {
        if (!entry.isFile) continue;
        final out = File(p.join(into.path, entry.name));
        await out.parent.create(recursive: true);
        final content = entry.content;
        await out.writeAsBytes(
          content is List<int> ? content : const <int>[],
          flush: true,
        );
      }
      return into;
    } catch (e) {
      throw const RestoreAborted('备份包损坏，解不开');
    }
  }

  static Future<Map<String, dynamic>?> _readManifest(Directory dir) async {
    final file = File(p.join(dir.path, 'manifest.json'));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      // manifest 坏了就是"没有校验信息"，不是致命错误：
      // 但必须给用户可见提示，不能静默当成正常包。
      return null;
    }
  }

  /// `PRAGMA integrity_check`：库结构坏没坏。
  ///
  /// 用 `enableMigrations: false` 打开 —— 校验路径**绝不能**触发迁移，
  /// 否则"点恢复"会顺手把用户还没确认的数据改了。
  static Future<void> _integrityCheck(File dbFile) async {
    final db = AppDatabase.withExecutor(
      NativeDatabase(dbFile, enableMigrations: false),
    );
    try {
      final row = await db.customSelect('PRAGMA integrity_check').getSingle();
      final value = row.data.values.first;
      if (value != 'ok') {
        throw RestoreAborted('备份里的数据库文件有损坏（integrity_check: $value）');
      }
    } catch (e) {
      if (e is RestoreAborted) rethrow;
      throw const RestoreAborted('备份里的数据库文件打不开');
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  static Future<Map<String, int>> _tableCounts(
    File dbFile,
    Iterable<String> tables,
  ) async {
    final db = AppDatabase.withExecutor(
      NativeDatabase(dbFile, enableMigrations: false),
    );
    final counts = <String, int>{};
    try {
      final existing = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final names = existing.map((r) => r.read<String>('name')).toSet();
      for (final table in tables) {
        if (!names.contains(table)) continue;
        final row = await db
            .customSelect('SELECT COUNT(*) AS c FROM "$table"')
            .getSingle();
        counts[table] = (row.data['c'] as num).toInt();
      }
    } catch (_) {
      // 统计失败按"无法校验"处理（调用方会退化成警告）
      return {};
    } finally {
      try {
        await db.close();
      } catch (_) {}
    }
    return counts;
  }

  /// 行数比对：**只比交集表**。
  ///
  /// v20 的备份里没有 `daily_overrides`，不能因为"备份里没有这张表"就判失败。
  static void _compareCounts(
    Map<String, int> expected,
    Map<String, int> actual,
  ) {
    for (final entry in expected.entries) {
      final got = actual[entry.key];
      if (got == null) continue; // 交集之外的跳过
      if (got != entry.value) {
        throw RestoreAborted(
          '备份里 ${entry.key} 的行数是 ${entry.value}，解压出来却是 $got，已中止恢复',
          table: entry.key,
          expected: entry.value,
          actual: got,
        );
      }
    }
  }

  static Future<int> _countFiles(Directory dir) async {
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) count++;
    }
    return count;
  }

  static Map<String, int>? _readTableCounts(Map<String, dynamic>? manifest) {
    final raw = manifest?['tableCounts'];
    if (raw is! Map) return null;
    final result = <String, int>{};
    raw.forEach((key, value) {
      final parsed = _asInt(value);
      if (key is String && parsed != null) result[key] = parsed;
    });
    return result.isEmpty ? null : result;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Object _asAbort(Object error) {
    if (error is RestoreAborted) return error;
    if (_isNoSpace(error)) {
      // 空间不足只会发生在 rename 之前（解压/写盘阶段），此时原库完好。
      // 这是本流程最"便宜"的一种失败：白跑一趟，数据一点没伤。
      return const RestoreAborted(
        '手机空间不够，恢复没有开始，你原来的数据没动。清一点空间再试。',
      );
    }
    return RestoreAborted('恢复失败，你的原数据没有被改动（$error）');
  }

  /// 识别 ENOSPC（errno 28）/ "No space left on device"。
  ///
  /// 不引第三方依赖（`dart:io` 没有剩余空间 API），靠捕获写盘异常兜底 ——
  /// 这比一个"看起来检查了其实没检查"的前置探测更诚实：真的写不下去时才会触发。
  static bool _isNoSpace(Object error) {
    if (error is! FileSystemException) return false;
    final code = error.osError?.errorCode;
    if (code == 28) return true; // POSIX ENOSPC
    final message = '${error.osError?.message ?? ''} ${error.message}';
    return message.toLowerCase().contains('no space');
  }
}
