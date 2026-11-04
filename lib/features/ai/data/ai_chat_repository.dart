import 'package:drift/drift.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';

/// AI 教练聊天记录仓库（Drift）
///
/// - 历史按时间正序返回（内部倒序取最近 [maxHistory] 条再反转）
/// - id 作为同毫秒消息的次级排序，保证顺序稳定
/// - v24：`chips` 列随消息一起读写（null = 无芯片，老数据天然兼容）
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
        .map((r) => AiMessage(
              role: r.role,
              content: r.content,
              // null / '' / 非法 JSON → 空列表，不需要任何 backfill
              chips: CoachChip.decode(r.chips),
            ))
        .toList();
  }

  /// 追加一条消息（user / assistant）
  ///
  /// [chips] 只在"本轮最终回复"那一次带；工具跟话说的话与留痕一律不带（C6）。
  Future<void> add(
    String role,
    String content, {
    List<CoachChip> chips = const [],
  }) async {
    await _db.into(_db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(
            role: role,
            content: content,
            chips: Value(CoachChip.encode(chips)),
          ),
        );
  }

  /// 清空聊天记录
  Future<void> clear() async {
    await _db.delete(_db.aiChatMessages).go();
  }
}
