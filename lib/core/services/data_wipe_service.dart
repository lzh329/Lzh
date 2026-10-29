import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';
import 'backup_service.dart';

/// 一键清空全部数据（毁灭性操作，服务层只负责"能安全地做"）。
///
/// 顺序是硬约束：**先备份，再清空**。备份失败就中止 —— 宁可不清，
/// 也不能让用户在没有备份的状态下裸删全部数据。
class DataWipeService {
  DataWipeService._();

  /// 会清空的表（名字与 `database.g.dart` 实际表名一致）
  static const List<String> tableNames = [
    'workout_sets',
    'workouts',
    'workout_templates',
    'workout_template_exercises',
    'body_metrics',
    'goals',
    'photos',
    'user_settings',
    'food_library',
    'food_log',
    'water_log',
    'ai_chat_messages',
    'daily_overrides',
  ];

  /// 执行清空。
  ///
  /// [db] 由调用方注入（走 `databaseProvider`，恢复/封存语义由外层负责）。
  /// 返回报告：备份包路径 + 各表删除行数。
  static Future<Map<String, dynamic>> wipeAll({
    required AppDatabase db,

    /// 文档目录（null = 走 path_provider）。单测注入临时目录，避免碰平台通道。
    Directory? docsDir,
  }) async {
    final docs = docsDir ?? await getApplicationDocumentsDirectory();

    // ── 1) 先备份；失败即中止（不许裸删）──
    final archive = await BackupService.createArchive(
      dbPath: p.join(docs.path, 'fittrack.sqlite'),
      photosDir: Directory(p.join(docs.path, 'photos')),
      outputDir: Directory(p.join(docs.path, 'backups')),
      fileName: 'pre-wipe-${BackupService.stamp(DateTime.now())}.zip',
      tableCounts: await _tableCounts(db),
    );

    // ── 2) 清空所有用户表（DELETE，不 DROP：schema 不变，迁移不受影响）──
    final deleted = <String, int>{};
    for (final table in tableNames) {
      final count = await _deleteAll(db, table);
      deleted[table] = count;
    }

    // ── 3) 照片文件（photos 表清了，磁盘文件也要清，否则残留孤儿文件）──
    final photosDir = Directory(p.join(docs.path, 'photos'));
    var photosDeleted = 0;
    if (await photosDir.exists()) {
      await for (final entity in photosDir.list(followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
            photosDeleted++;
          } catch (_) {}
        }
      }
    }

    return <String, dynamic>{
      'ok': true,
      'backup': p.basename(archive.path),
      'deleted': deleted,
      'photos_deleted': photosDeleted,
    };
  }

  /// 打包前的行数统计（写进备份的 manifest，供恢复侧对账）
  static Future<Map<String, int>> _tableCounts(AppDatabase db) async {
    final counts = <String, int>{};
    for (final table in tableNames) {
      counts[table] = await _count(db, table);
    }
    return counts;
  }

  static Future<int> _count(AppDatabase db, String table) async {
    final row =
        await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').getSingle();
    return (row.data['c'] as num).toInt();
  }

  static Future<int> _deleteAll(AppDatabase db, String table) async {
    final before = await _count(db, table);
    // DELETE 而不是 DROP：schema 必须保持不变，否则迁移状态就乱了
    await db.customStatement('DELETE FROM "$table"');
    return before;
  }
}
