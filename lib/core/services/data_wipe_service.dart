import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database.dart';
import 'backup_service.dart';

/// 一键清空全部数据（毁灭性操作，服务层只负责"能安全地做"）。
///
/// 顺序是硬约束：**先备份，再清空**。备份失败就中止 —— 宁可不清，
/// 也不能让用户在没有备份的状态下裸删全部数据。
///
/// 第二条硬约束：**清的是用户数据，不是内置字典**。内置食物 29 条、内置训练
/// 模板 5 个是"新装就有"的种子，只在 onCreate / 迁移里灌一次；user_version
/// 已经推到最新之后不会再重跑，删了就真没了 —— 用户清完数据会发现饮食页
/// 选不到"白米饭"、快速开始页一个模板都没有。
class DataWipeService {
  DataWipeService._();

  /// 会清空的表（名字与 `database.g.dart` 实际表名一致）
  ///
  /// 顺序同样是硬约束：子表先于父表。`workout_template_exercises` 必须排在
  /// `workout_templates` **之前**，因为它的删除范围是"模板将被删掉的那些"，
  /// 反过来先删模板，子查询就查不到任何行了。
  static const List<String> tableNames = [
    'workout_sets',
    'workouts',
    'workout_template_exercises',
    'workout_templates',
    'body_metrics',
    'goals',
    'photos',
    'user_settings',
    'food_log',
    'food_library',
    'water_log',
    'ai_chat_messages',
    'daily_overrides',
    // 周报是 AI 按当时的记录生成的文本，记录清了它还留着就是"数据没清干净"：
    // 下次生成前用户会在缓存里看到已经删掉的体重/训练。
    'weekly_report_cache',
  ];

  /// 混着"内置数据"和"用户数据"的表 —— 清空时只删用户自己加的行。
  ///
  /// 值是一段 SQL 谓词；`_deleteAll` 与 [deleteScopeOf] 都从这里取，
  /// UI（AI 确认卡的行数预览）也用同一份，避免"说要删 31 条其实只删 2 条"。
  static const Map<String, String> userScopeOf = {
    'food_library': 'is_custom = 1',
    'workout_template_exercises':
        'template_id IN (SELECT id FROM workout_templates WHERE is_recommended = 0)',
    'workout_templates': 'is_recommended = 0',
  };

  /// 某张表在"清空"时实际删除的范围（空串 = 整表删）
  static String deleteScopeOf(String table) {
    final scope = userScopeOf[table];
    return scope == null ? '' : ' WHERE $scope';
  }

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

    // ── 2) 清空用户数据（DELETE，不 DROP：schema 不变，迁移不受影响）──
    //
    // 整段包一个事务：中途失败就整体回滚，不留"一半清了一半没清"的库 ——
    // 那种库既不像清空前也不像清空后，用户和我们都判断不了他在哪一档。
    final deleted = <String, int>{};
    await db.transaction(() async {
      for (final table in tableNames) {
        deleted[table] = await _deleteUserRows(db, table);
      }
      // 内置模板兜底补种：正常情况下一条都不会缺（它们不在删除范围里），
      // 但老版本清空过的库可能已经把内置模板删掉了 —— 顺手补齐，
      // 保证清空后回到"刚装好就能用"的状态。
      await seedBuiltInTemplates(db);
    });

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
  ///
  /// 这里数的是**整表**行数（含内置字典）：备份包里本来就含全部内容，
  /// 对账口径必须和包里一致。别拿 [deleteScopeOf] 来数 —— 那是删除范围。
  static Future<Map<String, int>> _tableCounts(AppDatabase db) async {
    final counts = <String, int>{};
    for (final table in tableNames) {
      counts[table] = await _count(db, table);
    }
    return counts;
  }

  static Future<int> _count(
    AppDatabase db,
    String table, {
    String scope = '',
  }) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS c FROM "$table"$scope')
        .getSingle();
    return (row.data['c'] as num).toInt();
  }

  /// 删掉这张表里的**用户数据**，返回实际删除的行数
  static Future<int> _deleteUserRows(AppDatabase db, String table) async {
    final scope = deleteScopeOf(table);
    final before = await _count(db, table, scope: scope);
    // DELETE 而不是 DROP：schema 必须保持不变，否则迁移状态就乱了
    await db.customStatement('DELETE FROM "$table"$scope');
    return before;
  }
}
