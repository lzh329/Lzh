import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';

void main() {
  late AppDatabase db;
  late DailyOverrideRepository repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = DailyOverrideRepository(db);
  });

  tearDown(() async => db.close());

  final day = DateTime(2025, 3, 4);

  Future<int> rowCount() async {
    final rows = await db.select(db.dailyOverrides).get();
    return rows.length;
  }

  group('daily_overrides 数据层', () {
    test('无覆盖时 getByDate 返回 null（不造默认值）', () async {
      expect(await repo.getByDate(day), isNull);
      expect(await rowCount(), 0);
    });

    test('同一天 upsert 两次 → 只有 1 行，第二次覆盖', () async {
      await repo.upsert(date: day, calorieTargetOverride: 1800, source: 'user');
      await repo.upsert(
          date: day, calorieTargetOverride: 1500, source: 'ai_health');

      expect(await rowCount(), 1);
      final o = await repo.getByDate(day);
      expect(o, isNotNull);
      expect(o!.calorieTargetOverride, 1500, reason: '第二次写覆盖第一次');
      expect(o.source, 'ai_health');
    });

    test('同一天不同时刻 upsert → 仍是同一行（date 规整到 0 点）', () async {
      await repo.upsert(
          date: DateTime(2025, 3, 4, 9), setsScale: 0.8, source: 'user');
      await repo.upsert(
          date: DateTime(2025, 3, 4, 21),
          calorieTargetOverride: 1400,
          source: 'user');

      expect(await rowCount(), 1);
      final rows = await db.select(db.dailyOverrides).get();
      expect(rows.single.date, DateTime(2025, 3, 4));

      final o = await repo.getByDate(DateTime(2025, 3, 4, 21));
      expect(o!.calorieTargetOverride, 1400);
      expect(o.setsScale, closeTo(0.8, 1e-9), reason: '9 点那次写的还在');
    });

    test('只传 setsScale → calorieTargetOverride / reminderPaused 保持原值',
        () async {
      await repo.upsert(
        date: day,
        calorieTargetOverride: 1600,
        reminderPaused: true,
        macroJudgement: 'skip',
        source: 'user',
      );
      await repo.upsert(date: day, setsScale: 0.5, source: 'user');

      final o = await repo.getByDate(day);
      expect(o!.calorieTargetOverride, 1600, reason: '没传的字段不许被冲掉');
      expect(o.setsScale, closeTo(0.5, 1e-9));
      expect(o.reminderPaused, isTrue, reason: '不许用 false 兜底冲掉 true');
      expect(o.macroJudgement, 'skip');
    });

    test('未设置的字段读出来是 null，不是 0 / false', () async {
      await repo.upsert(date: day, source: 'user');

      final o = await repo.getByDate(day);
      expect(o!.calorieTargetOverride, isNull);
      expect(o.setsScale, isNull);
      expect(o.reminderPaused, isFalse, reason: 'NOT NULL DEFAULT 0，就是 false');
      expect(o.macroJudgement, 'normal');
      expect(o.createdAt, isNotNull);
    });

    test('第二次 upsert 不改写 createdAt', () async {
      await repo.upsert(date: day, setsScale: 0.9, source: 'user');
      final first = await repo.getByDate(day);
      await repo.upsert(date: day, setsScale: 0.6, source: 'user');
      final second = await repo.getByDate(day);
      expect(second!.createdAt, first!.createdAt);
      expect(second.setsScale, closeTo(0.6, 1e-9));
    });

    test('clear 后当天回到"没有覆盖"', () async {
      await repo.upsert(
          date: day, calorieTargetOverride: 1500, source: 'ai_health');
      expect(await repo.getByDate(day), isNotNull);

      await repo.clear(day);
      expect(await repo.getByDate(day), isNull);
      expect(await rowCount(), 0, reason: '撤销 = 删掉那行，不是把值改成默认');
    });

    test('不同日期各一条 → listRange 都能取到', () async {
      final d2 = DateTime(2025, 3, 6);
      final d3 = DateTime(2025, 3, 7);
      await repo.upsert(date: day, calorieTargetOverride: 1500, source: 'user');
      await repo.upsert(date: d2, setsScale: 0.5, source: 'ai_health');
      await repo.upsert(date: d3, setsScale: 0.7, source: 'user');

      expect(await rowCount(), 3);

      final all = await repo.listRange(day, d3);
      expect(all.length, 3);
      expect(all.map((o) => o.date), [day, d2, d3], reason: '按日期升序');

      final part = await repo.listRange(d2, d3);
      expect(part.length, 2);
      expect(part.first.date, d2);

      // 区间外不串；单日区间只取当天
      expect(await repo.listRange(DateTime(2025, 3, 5), DateTime(2025, 3, 5)),
          isEmpty);
      expect((await repo.listRange(d2, d2)).single.date, d2);
    });

    test('source 非法 → 抛 ArgumentError，且不落库', () async {
      await expectLater(
        repo.upsert(date: day, source: 'sleep'),
        throwsArgumentError,
        reason: 'sleep 是预留值，本期不接受',
      );
      await expectLater(
        repo.upsert(date: day, source: ''),
        throwsArgumentError,
      );
      expect(await rowCount(), 0, reason: '校验不通过就不许写进去');
    });

    test('source 合法的两个值都能写入', () async {
      await repo.upsert(date: day, source: 'user');
      await repo.upsert(date: DateTime(2025, 3, 5), source: 'ai_health');

      expect((await repo.getByDate(day))!.source, 'user');
      expect((await repo.getByDate(DateTime(2025, 3, 5)))!.source, 'ai_health');
    });
  });
}
