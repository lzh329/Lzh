import 'package:drift/drift.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/ai_service.dart';

/// AI 教练聊天记录仓库（Drift）
///
/// - 历史按时间正序返回（内部倒序取最近 [maxHistory] 条再反转）
/// - id 作为同毫秒消息的次级排序，保证顺序稳定
class AiChatRepository {
  static const int maxHistory = 60;

  final AppDatabase _db;
  AiChatRepository(this._db);

  /// 最近的历史消息（时间正序）
  Future<List<AiMessage>> getHistory() async {
    final rows = await (_db.select(_db.aiChatMessages)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(maxHistory))
        .get();
    return rows
        .reversed
        .map((r) => AiMessage(role: r.role, content: r.content))
        .toList();
  }

  /// 追加一条消息（user / assistant）
  Future<void> add(String role, String content) async {
    await _db.into(_db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(role: role, content: content),
        );
  }

  /// 清空聊天记录
  Future<void> clear() async {
    await _db.delete(_db.aiChatMessages).go();
  }
}
