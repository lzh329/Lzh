import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/db_replaced_marker.dart';

/// 数据库自动备份服务
///
/// - 备份存放在应用文档目录 `backups/` 下（时间戳命名）
/// - 同时维护一份 `fittrack_backup_latest.sqlite`，与「恢复数据库」打通
/// - 每次启动检查：距上次备份超过 [intervalDays] 天且开关打开 → 自动备份
/// - 只保留最近 [keep] 份，旧的自动清理
class AutoBackupService {
  static const int intervalDays = 7;
  static const int keep = 4;

  static Future<Directory> backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> get _dbPath async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/fittrack.sqlite';
  }

  /// 备份目录里的历史备份（按文件名时间戳倒序）
  ///
  /// ⚠️ 只认 `fittrack_backup_` 前缀。同目录下的 `pre-restore-*.sqlite`
  /// （恢复前安全副本）与 `broken-*.sqlite`（排查用坏库导出）**不算额度、
  /// 永不参与清理** —— 否则用户恢复几次后，安全网正好在他最需要的时候被轮转掉。
  static Future<List<File>> listBackups() async {
    final dir = await backupDir();
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.sqlite') &&
            p.basename(f.path).startsWith('fittrack_backup_'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  /// 最近一次备份时间（无备份返回 null）
  static Future<DateTime?> lastBackupAt() async {
    final files = await listBackups();
    if (files.isEmpty) return null;
    final stat = await files.first.stat();
    return stat.modified;
  }

  /// 立即备份一次（时间戳文件 + latest 镜像 + 清理旧备份）
  static Future<String> backupNow() async {
    final dir = await backupDir();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final target = File('${dir.path}/fittrack_backup_$stamp.sqlite');
    final dbPath = await _dbPath;
    final db = File(dbPath);
    if (!await db.exists()) {
      throw StateError('数据库文件不存在');
    }
    await db.copy(target.path);
    // latest 镜像：供「恢复数据库」直接使用
    await db.copy('${dir.path}/fittrack_backup_latest.sqlite');
    await _prune(dir);
    return target.path;
  }

  /// 启动时检查是否需要自动备份
  ///
  /// 返回：`disabled` / `sealed` / `skipped` / `backed-up` / `error`
  ///
  /// [isDbReplaced] 可注入，默认读 `db_replaced` 标记。
  static Future<String> runIfNeeded({
    required bool enabled,
    Future<bool> Function()? isDbReplaced,
  }) async {
    if (!enabled) return 'disabled';

    // 库可能刚被换掉（或正在换）：**根本不启动**这次备份。
    //
    // 注意这不是"捕获异常打日志"——`sealed` 态下打开库会抛，但那时已经
    // 白跑一趟；更要紧的是恢复/退回流程中间那段窗口里，备份会读到半新半旧的
    // 数据并把它写成"官方备份"，那比不备份危险得多。
    try {
      final replaced = await (isDbReplaced ?? DbReplacedMarker.exists)();
      if (replaced) return 'sealed';
    } catch (_) {
      return 'sealed'; // 判断不出来就按"别备份"处理
    }
    if (DatabaseSeal.sealed) return 'sealed';
    try {
      final last = await lastBackupAt();
      if (last != null &&
          DateTime.now().difference(last) <
              const Duration(days: intervalDays)) {
        return 'skipped';
      }
      await backupNow();
      return 'backed-up';
    } catch (e) {
      debugPrint('自动备份失败: $e');
      return 'error';
    }
  }

  /// 只保留最近 [keep] 份时间戳备份（latest 镜像不参与清理）
  static Future<void> _prune(Directory dir) async {
    final files = await listBackups();
    for (var i = keep; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }
}
