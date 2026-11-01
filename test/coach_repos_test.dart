import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/coach_memory_repository.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';

/// v24 两张新表的存取语义（W-3 / M-5 / M-6 / M-16 后半）
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  CoachProactiveRepository proactive() => CoachProactiveRepository(db);
  CoachMemoryRepository memories() => CoachMemoryRepository(db);

  CoachProactiveMessagesCompanion weeklyCompanion({
    String key = 'weekly:2025-11-17',
    DateTime? weekStart,
    DateTime? seenAt,
  }) =>
      CoachProactiveMessagesCompanion.insert(
        kind: 'weekly',
        dedupeKey: key,
        content: '上周练了 2 次，一共 40 分钟。',
        source: 'template',
        weekStart: Value(weekStart ?? DateTime(2025, 11, 17)),
        seenAt: Value(seenAt),
      );

  // ═══════════ coach_proactive_messages ═══════════

  group('coach_proactive_messages', () {
    test('W-3：同一 dedupe_key 直接 insert 两次，第二次被数据库拒绝（不是靠代码 if）', () async {
      await db.into(db.coachProactiveMessages).insert(weeklyCompanion());
      await expectLater(
        db.into(db.coachProactiveMessages).insert(weeklyCompanion()),
        throwsA(anything),
        reason: '唯一约束必须由数据库自己兜住',
      );
      expect(await db.select(db.coachProactiveMessages).get(), hasLength(1));
    });

    test('insertIfAbsent：第二次返回 null（视为已生成），不是失败', () async {
      final first = await proactive().insertIfAbsent(weeklyCompanion());
      expect(first, isNotNull);
      final second = await proactive().insertIfAbsent(weeklyCompanion());
      expect(second, isNull, reason: 'null = 该 dedupeKey 已存在，调用方静默跳过');
      expect(await db.select(db.coachProactiveMessages).get(), hasLength(1));
    });

    test('markSeen 只在 seen_at IS NULL 时写，重复调用不刷新首次阅读时间', () async {
      final record = (await proactive().insertIfAbsent(weeklyCompanion()))!;
      final t1 = DateTime(2025, 11, 17, 8);
      final t2 = DateTime(2025, 11, 18, 9);

      expect(await proactive().markSeen(record.id, t1), isTrue);
      expect(await proactive().markSeen(record.id, t2), isFalse,
          reason: 'WHERE seen_at IS NULL 保证幂等');
      final after = (await proactive().getByDedupeKey(record.dedupeKey))!;
      expect(after.seenAt, t1);
    });

    test('getWeekly 只在当周 7 天区间内命中，跨周不会读错', () async {
      final thisWeek = DateTime(2025, 11, 17);
      final lastWeek = DateTime(2025, 11, 10);
      await proactive()
          .insertIfAbsent(weeklyCompanion(weekStart: lastWeek, key: 'weekly:a'));
      expect(await proactive().getWeekly(thisWeek), isNull);
      expect(await proactive().getWeekly(lastWeek), isNotNull);
    });

    test('recentWeekly 按 week_start 倒序且受 limit 约束（降频判定用）', () async {
      for (final d in [
        DateTime(2025, 11, 3),
        DateTime(2025, 11, 10),
        DateTime(2025, 11, 17),
      ]) {
        await proactive().insertIfAbsent(weeklyCompanion(
          key: 'weekly:${d.toIso8601String()}',
          weekStart: d,
        ));
      }
      final recent = await proactive().recentWeekly(limit: 2);
      expect(recent, hasLength(2));
      expect(recent.first.weekStart, DateTime(2025, 11, 17));
    });

    test('listKindBetween 只返回区间内的该类消息（点评内展用它）', () async {
      final base = DateTime(2025, 11, 17, 10);
      await proactive().insertIfAbsent(CoachProactiveMessagesCompanion.insert(
        kind: 'workout_recap',
        dedupeKey: 'recap:1',
        content: '刚那 28 分钟力量练得挺实在。',
        source: 'template',
        workoutId: const Value(1),
        createdAt: Value(base),
      ));
      final today = await proactive().listKindBetween(
        kind: 'workout_recap',
        from: DateTime(2025, 11, 17),
        to: DateTime(2025, 11, 18),
      );
      expect(today, hasLength(1));
      expect(
        await proactive().listKindBetween(
          kind: 'workout_recap',
          from: DateTime(2025, 11, 18),
          to: DateTime(2025, 11, 19),
        ),
        isEmpty,
      );
      expect(
        await proactive().listKindBetween(
          kind: 'weekly',
          from: DateTime(2025, 11, 17),
          to: DateTime(2025, 11, 18),
        ),
        isEmpty,
        reason: 'kind 必须真的参与过滤',
      );
    });

    test('countKindBetween 按创建时间区间计数（点评"本周最多 2 条"用它）', () async {
      for (var i = 1; i <= 3; i++) {
        await proactive().insertIfAbsent(CoachProactiveMessagesCompanion.insert(
          kind: 'workout_recap',
          dedupeKey: 'recap:$i',
          content: '练完了',
          source: 'template',
          workoutId: Value(i),
          createdAt: Value(DateTime(2025, 11, 17, i)),
        ));
      }
      expect(
        await proactive().countKindBetween(
          kind: 'workout_recap',
          from: DateTime(2025, 11, 17),
          to: DateTime(2025, 11, 24),
        ),
        3,
      );
      expect(
        await proactive().countKindBetween(
          kind: 'workout_recap',
          from: DateTime(2025, 11, 18),
          to: DateTime(2025, 11, 24),
        ),
        0,
      );
    });
  });

  // ═══════════ coach_memories ═══════════

  group('coach_memories', () {
    CoachMemoriesCompanion mem({
      String category = 'injury',
      String topic = '右膝',
      String content = '右膝半月板有旧伤',
      String quote = '我右膝半月板有旧伤',
    }) =>
        CoachMemoriesCompanion.insert(
          category: category,
          topic: topic,
          content: content,
          quote: quote,
          updatedAt: Value(DateTime(2025, 11, 17)),
        );

    test('M-5：同 (category, topic) 二次写入只 1 行且内容被覆盖', () async {
      await memories().upsert(mem());
      await memories().upsert(mem(
        content: '膝盖已经好了',
        quote: '我膝盖好了',
      ));
      final all = await memories().listAll();
      expect(all, hasLength(1));
      expect(all.single.content, '膝盖已经好了');
      expect(all.single.quote, '我膝盖好了');
    });

    test('不同 topic 是两条（唯一键是复合键，不是 category 单列）', () async {
      await memories().upsert(mem());
      await memories().upsert(mem(topic: '左膝', content: '左膝有点酸', quote: '左膝有点酸'));
      expect(await memories().count(), 2);
      expect(await memories().countByCategory(), {'injury': 2});
    });

    test('M-6：deleteByKey 命中返回 true；不存在返回 false 且不抛', () async {
      await memories().upsert(mem());
      expect(await memories().deleteByKey('injury', '右膝'), isTrue);
      expect(await memories().deleteByKey('injury', '右膝'), isFalse);
      expect(await memories().count(), 0);
    });

    test('deleteById 返回被删行（供 5 秒撤销），reinsert 能回来', () async {
      final saved = await memories().upsert(mem());
      final removed = await memories().deleteById(saved!.id);
      expect(removed, isNotNull);
      expect(await memories().count(), 0);

      await memories().reinsert(removed!);
      final restored = await memories().listAll();
      expect(restored, hasLength(1));
      expect(restored.single.content, '右膝半月板有旧伤');
    });

    test('reinsert 撞上同一 (category, topic) 时不抛异常，走覆盖路径', () async {
      final saved = (await memories().upsert(mem()))!;
      await memories().deleteById(saved.id);
      // 5 秒内被新的记忆占用同一个键
      await memories().upsert(mem(content: '膝盖已经好了', quote: '膝盖好了'));
      await memories().reinsert(saved);
      expect(await memories().count(), 1, reason: '不许撞唯一键把撤销变成崩溃点');
    });

    test('touch 只更新命中条目的 last_used_at', () async {
      final a = (await memories().upsert(mem()))!;
      await memories().upsert(mem(topic: '左膝', content: '左膝有点酸', quote: '左膝有点酸'));
      final at = DateTime(2025, 11, 18);
      await memories().touch([a.id], at);
      final rows = await memories().listAll();
      final touched = rows.firstWhere((m) => m.id == a.id);
      final other = rows.firstWhere((m) => m.id != a.id);
      expect(touched.lastUsedAt, at);
      expect(other.lastUsedAt, isNull);
    });

    test('clearAll 清空', () async {
      await memories().upsert(mem());
      expect(await memories().deleteAll(), 1);
      expect(await memories().count(), 0);
    });
  });

  // ═══════════ 与 wipe_all_data 的关系（M-16 后半） ═══════════

  test('M-16：wipeAll 后 coach_memories / coach_proactive_messages 都是 0 行', () async {
    final docs = await Directory.systemTemp.createTemp('fittrack_wipe_v24');
    try {
      final fileDb = AppDatabase.withExecutor(
          NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))));
      await fileDb.customSelect('SELECT 1').get();
      await fileDb.close();

      await memories().upsert(CoachMemoriesCompanion.insert(
        category: 'diet',
        topic: '香菜',
        content: '不吃香菜',
        quote: '我不吃香菜',
      ));
      await proactive().insertIfAbsent(weeklyCompanion());
      expect(await memories().count(), 1);

      final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

      expect((report['deleted'] as Map<String, int>)['coach_memories'], 1);
      expect((report['deleted'] as Map<String, int>)['coach_proactive_messages'], 1);
      expect(await memories().count(), 0);
      expect(await db.select(db.coachProactiveMessages).get(), isEmpty);
    } finally {
      try {
        if (await docs.exists()) await docs.delete(recursive: true);
      } catch (_) {}
    }
  });
}
