import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

void main() {
  late AppDatabase db;
  late DailyOverrideRepository repo;
  late SickDayGate gate;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = DailyOverrideRepository(db);
    gate = SickDayGate(repo, UserSettingsRepositoryImpl(db));
  });

  tearDown(() async => db.close());

  final day = DateTime(2025, 3, 4);

  Future<int> rowCount() async {
    final rows = await db.select(db.dailyOverrides).get();
    return rows.length;
  }

  group('纯函数：组数缩放 / 热量放宽', () {
    test('T03-B4 scaleSets：null 原样、0.5 减半、下限 1 组', () {
      expect(SickDayGate.scaleSets(4, null), 4, reason: '未设置就不缩放');
      expect(SickDayGate.scaleSets(4, 0.5), 2);
      expect(SickDayGate.scaleSets(3, 0.3), 1, reason: '0.9 四舍五入到 1，不是 0');
      expect(SickDayGate.scaleSets(1, 0.1), 1,
          reason: '下限 1 组：0 组等于把计划抹掉，还会引出空列表边界');
    });

    test('T03-B6 relaxCalorieTarget：只放宽、不加严', () {
      expect(SickDayGate.relaxCalorieTarget(2000, 2200), 2200,
          reason: '放宽 → 采纳');
      expect(SickDayGate.relaxCalorieTarget(2000, 1500), 2000,
          reason: '比全局目标还小 = 加严，不采纳');
      expect(SickDayGate.relaxCalorieTarget(2000, null), 2000);
      expect(SickDayGate.relaxCalorieTarget(2000, 2000), 2000);
    });
  });

  group('apply / revoke', () {
    test('T03-A1 当天无覆盖 → overrideFor 为 null、isActive 为 false', () async {
      expect(await gate.overrideFor(day), isNull, reason: '不造默认值');
      expect(await gate.isActive(day), isFalse);
      expect(await rowCount(), 0);
    });

    test('apply 后 isActive 为 true、overrideFor 能取回写的字段', () async {
      await gate.apply(
        date: day,
        calorieTargetOverride: 2200,
        setsScale: 0.5,
        reminderPaused: true,
        source: 'user',
      );

      expect(await gate.isActive(day), isTrue);
      final o = await gate.overrideFor(day);
      expect(o, isNotNull);
      expect(o!.calorieTargetOverride, 2200);
      expect(o.setsScale, closeTo(0.5, 1e-9));
      expect(o.reminderPaused, isTrue);
      expect(o.source, 'user');
      expect(await rowCount(), 1);
    });

    test('T03-A2/A3 同日再 apply：只有 1 行，且只改传入的字段', () async {
      await gate.apply(
        date: day,
        calorieTargetOverride: 2200,
        reminderPaused: true,
        source: 'ai_health',
      );
      await gate.apply(date: day, setsScale: 0.5, source: 'ai_health');

      expect(await rowCount(), 1, reason: '一天一行，第二次是覆盖不是新增');
      final o = await gate.overrideFor(day);
      expect(o!.calorieTargetOverride, 2200, reason: '没传的字段不许被冲掉');
      expect(o.setsScale, closeTo(0.5, 1e-9));
      expect(o.reminderPaused, isTrue, reason: '不许用 false 兜底冲掉 true');
      expect(o.source, 'ai_health');
    });

    test('T03-A5 revoke 后回到 null —— 不是返回一条默认值', () async {
      await gate.apply(date: day, setsScale: 0.5, source: 'ai_health');
      await gate.revoke(day);

      expect(await gate.overrideFor(day), isNull);
      expect(await gate.isActive(day), isFalse);
      expect(await rowCount(), 0, reason: '撤销 = 删掉那行，不是把值改成默认');
    });

    test('T03-A6 listRange 闭区间、按日期升序、不串到区间外', () async {
      final d2 = DateTime(2025, 3, 6);
      await gate.apply(date: day, setsScale: 0.5, source: 'user');
      await gate.apply(date: d2, setsScale: 0.7, source: 'ai_health');

      expect((await repo.listRange(day, d2)).map((o) => o.date), [day, d2]);
      expect((await repo.listRange(d2, d2)).single.date, d2);
      expect(
        await repo.listRange(DateTime(2025, 3, 5), DateTime(2025, 3, 5)),
        isEmpty,
      );
    });

    test('T03-A4 apply 的 source 非法 → ArgumentError 且不落库', () async {
      await expectLater(
        gate.apply(date: day, setsScale: 0.5, source: 'sleep'),
        throwsArgumentError,
        reason: 'sleep 是预留值，本期不接受',
      );
      await expectLater(
        gate.apply(date: day, setsScale: 0.5, source: ''),
        throwsArgumentError,
      );
      expect(await rowCount(), 0, reason: '校验不通过就不许写进去');
      expect(await gate.isActive(day), isFalse);
    });
  });
}
