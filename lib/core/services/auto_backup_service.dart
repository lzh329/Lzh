import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

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
  static Future<List<File>> listBackups() async {
    final dir = await backupDir();
    final files = (await dir.list().toList())
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
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
  /// 返回：'disabled' / 'skipped' / 'backed-up'（异常内部吞掉，返回 'error'）
  static Future<String> runIfNeeded({required bool enabled}) async {
    if (!enabled) return 'disabled';
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
