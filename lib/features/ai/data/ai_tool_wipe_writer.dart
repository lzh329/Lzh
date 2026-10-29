import 'dart:convert';

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 一键清空全部数据（毁灭性操作：红卡 + 二次确认由确认卡 UI 负责）
///
/// preview 列出将删数据的统计（各表行数 + 照片数），execute 调
/// [DataWipeService] —— 它会**先自动备份**，备份失败就中止清空。
class AiToolWipeWriter extends AiToolHandler {
  AiToolWipeWriter(super.repos);

  @override
  Set<String> get toolNames => const {AiToolSpecs.wipeAllData};

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    final db = repos.database;
    final stats = <String>[];
    for (final table in DataWipeService.tableNames) {
      final row =
          await db.customSelect('SELECT COUNT(*) AS c FROM "$table"').getSingle();
      final count = (row.data['c'] as num).toInt();
      if (count > 0) stats.add('$table $count 条');
    }
    final photos = await _photoCount();
    if (photos > 0) stats.add('照片 $photos 张');

    return AiToolPreview(
      call: call,
      label: '清空全部数据',
      detail: stats.isEmpty
          ? '当前已经没有数据，但会清空全部表并留一份备份'
          : '将删除：${stats.join('、')}（自动留一份完整备份）',
      needsConfirm: true,
      isDestructive: true,
    );
  }

  @override
  Future<String> execute(AiToolCall call) async {
    final report = await DataWipeService.wipeAll(db: repos.database);
    return jsonEncode(report);
  }

  Future<int> _photoCount() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'photos'));
      if (!await dir.exists()) return 0;
      var count = 0;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}
