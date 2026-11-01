import 'package:drift/drift.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';

/// 教练记忆仓库 —— 只做存取，**不含策略**。
///
/// 上限淘汰顺序、注入挑选、候选校验全部在纯函数
/// `coach_memory_policy.dart` 里（可单测、零 IO）；这里只执行「删这几行 /
/// 写这一行」。这样"哪条该被淘汰"可以用内存列表直接证伪，不必造库。
class CoachMemoryRepository {
  CoachMemoryRepository(this._db);

  final AppDatabase _db;

  /// 全部记忆，[CoachMemory.updatedAt] 倒序（记忆页展示顺序）
  Future<List<CoachMemory>> listAll() async {
    final rows = await (_db.select(_db.coachMemories)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ]))
        .get();
    return rows.map(_toEntity).toList();
  }

  Future<CoachMemory?> getById(int id) async {
    final row = await (_db.select(_db.coachMemories)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  Future<int> count() async {
    final expr = _db.coachMemories.id.count();
    final row = await (_db.selectOnly(_db.coachMemories)..addColumns([expr]))
        .getSingle();
    return row.read(expr) ?? 0;
  }

  Future<Map<String, int>> countByCategory() async {
    final rows = await _db.customSelect(
      'SELECT category, COUNT(*) AS c FROM coach_memories GROUP BY category',
    ).get();
    return {
      for (final r in rows)
        r.read<String>('category'): r.read<int>('c'),
    };
  }

  /// `(category, topic)` 命中就覆盖 content / quote / updated_at，否则插入（M5）。
  ///
  /// 不用 `insertOnConflictUpdate`：它的冲突目标是主键，而这里的唯一键是
  /// `(category, topic)` 复合列 —— 走"先查后写"才与真实约束一致。
  Future<CoachMemory?> upsert(CoachMemoriesCompanion c) async {
    final category = c.category.value;
    final topic = c.topic.value;
    final existing = await (_db.select(_db.coachMemories)
          ..where((t) => t.category.equals(category) & t.topic.equals(topic))
          ..limit(1))
        .getSingleOrNull();
    if (existing == null) {
      final id = await _db.into(_db.coachMemories).insert(c);
      return getById(id);
    }
    await (_db.update(_db.coachMemories)
          ..where((t) => t.id.equals(existing.id)))
        .write(CoachMemoriesCompanion(
      content: c.content,
      quote: c.quote,
      sourceMessageId: c.sourceMessageId,
      updatedAt: c.updatedAt.present ? c.updatedAt : Value(DateTime.now()),
    ));
    return getById(existing.id);
  }

  /// 删该 `(category, topic)`；不存在返回 false，**不抛**（M6）
  Future<bool> deleteByKey(String category, String topic) async {
    final affected = await (_db.delete(_db.coachMemories)
          ..where((t) => t.category.equals(category) & t.topic.equals(topic)))
        .go();
    return affected > 0;
  }

  /// 删单条并返回被删的行（供 M14 的 5 秒撤销用）
  Future<CoachMemory?> deleteById(int id) async {
    final existing = await getById(id);
    if (existing == null) return null;
    await (_db.delete(_db.coachMemories)..where((t) => t.id.equals(id))).go();
    return existing;
  }

  /// 撤销删除：重新落一行。
  ///
  /// 5 秒内该 `(category, topic)` 可能已被新记忆占用 —— 走 [upsert] 的覆盖
  /// 路径而不是直接 insert，避免撞唯一键抛异常把撤销按钮变成崩溃点。
  Future<void> reinsert(CoachMemory m) async {
    await upsert(CoachMemoriesCompanion.insert(
      category: m.category,
      topic: m.topic,
      content: m.content,
      quote: m.quote,
      sourceMessageId: Value(m.sourceMessageId),
      createdAt: Value(m.createdAt),
      updatedAt: Value(m.updatedAt),
      lastUsedAt: Value(m.lastUsedAt),
    ));
  }

  /// 更新命中条目的 `last_used_at`（M10：注入即算"用过"）
  Future<void> touch(List<int> ids, DateTime at) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.coachMemories)..where((t) => t.id.isIn(ids)))
        .write(CoachMemoriesCompanion(lastUsedAt: Value(at)));
  }

  Future<int> deleteAll() => _db.delete(_db.coachMemories).go();

  CoachMemory _toEntity(CoachMemoryRow r) => CoachMemory(
        id: r.id,
        category: r.category,
        topic: r.topic,
        content: r.content,
        quote: r.quote,
        sourceMessageId: r.sourceMessageId,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        lastUsedAt: r.lastUsedAt,
      );
}
