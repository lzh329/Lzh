import 'package:drift/drift.dart';

import 'package:fittrack/core/database/database.dart';

/// 一条主动消息的投递记录（周消息 / 训练后点评）。
///
/// 只做数据搬运，不含任何策略：「推不推」「什么时候推」由
/// `coach_proactive_scheduler.dart` 里的纯函数决定。
class CoachProactiveMessage {
  final int id;

  /// `weekly` / `workout_recap`
  final String kind;

  /// `weekly:{yyyy-MM-dd}` / `recap:{workoutId}`（唯一键，靠数据库拒绝重复）
  final String dedupeKey;
  final String content;

  /// `ai` / `template`
  final String source;

  /// 该周周一 00:00（本地）；点评为 null
  final DateTime? weekStart;
  final int? workoutId;
  final DateTime createdAt;

  /// 渲染时写入；null = 未读
  final DateTime? seenAt;

  const CoachProactiveMessage({
    required this.id,
    required this.kind,
    required this.dedupeKey,
    required this.content,
    required this.source,
    required this.createdAt,
    this.weekStart,
    this.workoutId,
    this.seenAt,
  });

  bool get isSeen => seenAt != null;
}

/// 主动消息的投递记录仓库。
///
/// 去重唯一的可靠手段是**数据库的唯一约束**，不是代码里的 `if`：
/// 代码判断会遇到"两次生成都跑到 insert"（启动 + 回前台几乎同时），
/// 只有唯一键能兜住第二条。所以 [insertIfAbsent] 返回 null 表示
/// 「这个 dedupeKey 已经存在」，不是失败。
class CoachProactiveRepository {
  CoachProactiveRepository(this._db);

  final AppDatabase _db;

  Future<CoachProactiveMessage?> getById(int id) async {
    final row = await (_db.select(_db.coachProactiveMessages)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  Future<CoachProactiveMessage?> getByDedupeKey(String key) async {
    final row = await (_db.select(_db.coachProactiveMessages)
          ..where((t) => t.dedupeKey.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// 某一周（`weekStart` 起 7 天内）的周消息
  Future<CoachProactiveMessage?> getWeekly(DateTime weekStart) async {
    final end = weekStart.add(const Duration(days: 7));
    final row = await (_db.select(_db.coachProactiveMessages)
          ..where((t) =>
              t.kind.equals('weekly') &
              t.weekStart.isBiggerOrEqualValue(weekStart) &
              t.weekStart.isSmallerThanValue(end))
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// 本周最新一条周消息（首页气泡用：已读也返回，由调用方决定露不露）
  Future<CoachProactiveMessage?> getLatestWeekly() async {
    final row = await (_db.select(_db.coachProactiveMessages)
          ..where((t) => t.kind.equals('weekly'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.weekStart, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toEntity(row);
  }

  /// 最近 [limit] 条周消息（按 week_start 倒序），降频判定用（W14）
  Future<List<CoachProactiveMessage>> recentWeekly({int limit = 2}) async {
    final rows = await (_db.select(_db.coachProactiveMessages)
          ..where((t) => t.kind.equals('weekly'))
          ..orderBy([
            (t) => OrderingTerm(expression: t.weekStart, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows.map(_toEntity).toList();
  }

  /// `[from, to)` 区间内某类消息（按创建时间倒序）。
  ///
  /// 点评的内展与"同日只留 1 条"都基于它：区间查询比"取最新一条再比对日期"
  /// 更不容易被时区/跨天边界坑到。
  Future<List<CoachProactiveMessage>> listKindBetween({
    required String kind,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await (_db.select(_db.coachProactiveMessages)
          ..where((t) =>
              t.kind.equals(kind) &
              t.createdAt.isBiggerOrEqualValue(from) &
              t.createdAt.isSmallerThanValue(to))
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
          ]))
        .get();
    return rows.map(_toEntity).toList();
  }

  /// [from, to] 区间内某类消息的条数（点评的「本周最多 2 条」用它）
  Future<int> countKindBetween({
    required String kind,
    required DateTime from,
    required DateTime to,
  }) async {
    final expr = _db.coachProactiveMessages.id.count();
    final row = await (_db.selectOnly(_db.coachProactiveMessages)
          ..addColumns([expr])
          ..where(_db.coachProactiveMessages.kind.equals(kind) &
              _db.coachProactiveMessages.createdAt
                  .isBiggerOrEqualValue(from) &
              _db.coachProactiveMessages.createdAt.isSmallerThanValue(to)))
        .getSingle();
    return row.read(expr) ?? 0;
  }

  /// 返回 null = 该 dedupeKey 已存在（唯一约束拒绝），调用方视为「已生成」
  /// 静默跳过 —— 不是失败（W3）。
  Future<CoachProactiveMessage?> insertIfAbsent(
      CoachProactiveMessagesCompanion c) async {
    final key = c.dedupeKey.value;
    try {
      final id = await _db.into(_db.coachProactiveMessages).insert(c);
      return await getById(id);
    } catch (_) {
      // 用"回读确认"而不是匹配 SQLITE_CONSTRAINT_UNIQUE 错误码：drift 在不同
      // executor 下包装出的异常类型不同（SqliteException / DriftWrappedException），
      // 错误码匹配会在某个平台上静默失效。
      final existing = await getByDedupeKey(key);
      if (existing != null) return null;
      rethrow;
    }
  }

  /// 只在 `seen_at IS NULL` 时写；返回是否真的写了（幂等，W11）。
  ///
  /// 条件更新保证"首次阅读时间"不会被后续重建刷新成更晚的时间。
  Future<bool> markSeen(int id, DateTime at) async {
    final affected = await (_db.update(_db.coachProactiveMessages)
          ..where((t) => t.id.equals(id) & t.seenAt.isNull()))
        .write(CoachProactiveMessagesCompanion(seenAt: Value(at)));
    return affected > 0;
  }

  Future<int> deleteByDedupeKeys(Iterable<String> keys) async {
    final list = keys.toList();
    if (list.isEmpty) return 0;
    return (_db.delete(_db.coachProactiveMessages)
          ..where((t) => t.dedupeKey.isIn(list)))
        .go();
  }

  Future<int> deleteAll() => _db.delete(_db.coachProactiveMessages).go();

  CoachProactiveMessage _toEntity(CoachProactiveRow r) => CoachProactiveMessage(
        id: r.id,
        kind: r.kind,
        dedupeKey: r.dedupeKey,
        content: r.content,
        source: r.source,
        weekStart: r.weekStart,
        workoutId: r.workoutId,
        createdAt: r.createdAt,
        seenAt: r.seenAt,
      );
}
