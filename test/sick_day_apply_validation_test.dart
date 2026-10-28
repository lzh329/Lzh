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

  Future<int> rowCount() async {
    final rows = await db.select(db.dailyOverrides).get();
    return rows.length;
  }

  Future<void> setGlobalTarget(int target) async {
    await UserSettingsRepositoryImpl(db).save(dailyCalorieTarget: target);
  }

  final today = DateTime.now();

  group('T03-B5 setsScale 区间 (0.0, 1.0]', () {
    test('setsScale = 0 → ArgumentError 且不落库', () async {
      await expectLater(
        gate.apply(date: today, setsScale: 0, source: 'user'),
        throwsArgumentError,
        reason: '0 组等于把今天的计划抹掉，跟「藏起来」是同一个坑',
      );
      expect(await rowCount(), 0, reason: '校验不通过就不许写进去');
      expect(await gate.isActive(today), isFalse);
    });

    test('setsScale = 1.5 → ArgumentError 且不落库', () async {
      await expectLater(
        gate.apply(date: today, setsScale: 1.5, source: 'ai_health'),
        throwsArgumentError,
        reason: '> 1 是加量，生病的语义里没有这一项',
      );
      expect(await rowCount(), 0);
    });

    test('setsScale = 负值 / NaN → ArgumentError 且不落库', () async {
      await expectLater(
        gate.apply(date: today, setsScale: -0.5, source: 'user'),
        throwsArgumentError,
      );
      await expectLater(
        gate.apply(date: today, setsScale: double.nan, source: 'user'),
        throwsArgumentError,
        reason: 'NaN 不该被当成"没传"，它比 0 更危险',
      );
      expect(await rowCount(), 0);
    });
  });

  group('T03-B6 calorieTargetOverride 只放宽不加严', () {
    test('calorieTargetOverride = 0 → ArgumentError 且不落库', () async {
      await setGlobalTarget(2000);

      await expectLater(
        gate.apply(date: today, calorieTargetOverride: 0, source: 'user'),
        throwsArgumentError,
        reason: '0 千卡是饥饿目标，不是生病目标',
      );
      expect(await rowCount(), 0);
    });

    test('calorieTargetOverride = -100 → ArgumentError 且不落库', () async {
      await setGlobalTarget(2000);

      await expectLater(
        gate.apply(date: today, calorieTargetOverride: -100, source: 'user'),
        throwsArgumentError,
      );
      expect(await rowCount(), 0);
    });

    test('比全局目标小（加严）→ ArgumentError 且不落库', () async {
      await setGlobalTarget(2000);

      await expectLater(
        gate.apply(
            date: today, calorieTargetOverride: 1500, source: 'ai_health'),
        throwsArgumentError,
        reason: '生病时放宽是为了避免假警报；反向就是 App 劝你生病时少吃',
      );
      expect(await rowCount(), 0);
      expect(await gate.overrideFor(today), isNull);
    });

    test('比全局目标大（放宽）→ 正常落库', () async {
      await setGlobalTarget(2000);

      await gate.apply(
        date: today,
        calorieTargetOverride: 2200,
        source: 'ai_health',
      );

      final o = await gate.overrideFor(today);
      expect(o, isNotNull);
      expect(o!.calorieTargetOverride, 2200);
      expect(await rowCount(), 1);
    });

    test('等于全局目标 → 放行（既没放宽也没加严）', () async {
      await setGlobalTarget(2000);

      await gate.apply(
        date: today,
        calorieTargetOverride: 2000,
        source: 'user',
      );

      expect((await gate.overrideFor(today))!.calorieTargetOverride, 2000);
    });

    test('全局目标为 null → 没有可比对象，放过（不抛也不写 0）', () async {
      await gate.apply(
        date: today,
        calorieTargetOverride: 2200,
        source: 'user',
      );

      expect((await gate.overrideFor(today))!.calorieTargetOverride, 2200,
          reason: '用户没设全局目标时，UI 本来就显示「未设置」，没有假警报可谈');
    });
  });

  group('合法值回归（校验不能写死）', () {
    test('只传 setsScale → 正常落库，热量字段保持未设置', () async {
      await setGlobalTarget(2000);

      await gate.apply(date: today, setsScale: 0.5, source: 'user');

      final o = await gate.overrideFor(today);
      expect(o!.setsScale, closeTo(0.5, 1e-9));
      expect(o.calorieTargetOverride, isNull, reason: '没传就是未设置，不许兜 0');
      expect(o.reminderPaused, isFalse, reason: '没传就是没暂停，不许兜 true');
      expect(await rowCount(), 1);
    });

    test('三个字段全传 → 正常落库', () async {
      await setGlobalTarget(1800);

      await gate.apply(
        date: today,
        calorieTargetOverride: 2200,
        setsScale: 1.0,
        reminderPaused: true,
        source: 'ai_health',
      );

      final o = await gate.overrideFor(today);
      expect(o!.calorieTargetOverride, 2200);
      expect(o.setsScale, closeTo(1.0, 1e-9), reason: '1.0 是合法上界（不缩减）');
      expect(o.reminderPaused, isTrue);
      expect(SickDayGate.scaleSets(4, o.setsScale), 4);
    });

    test('不传任何字段 → 只写 source，其余保持 null', () async {
      await gate.apply(date: today, source: 'user');

      final o = await gate.overrideFor(today);
      expect(o, isNotNull);
      expect(o!.setsScale, isNull);
      expect(o.calorieTargetOverride, isNull);
      expect(o.reminderPaused, isFalse);
      expect(await rowCount(), 1);
    });

    test('校验失败不破坏已有数据：加严被拒后原来的行还在', () async {
      await setGlobalTarget(2000);
      await gate.apply(
        date: today,
        calorieTargetOverride: 2200,
        source: 'user',
      );

      await expectLater(
        gate.apply(date: today, calorieTargetOverride: 1000, source: 'user'),
        throwsArgumentError,
      );

      final o = await gate.overrideFor(today);
      expect(o!.calorieTargetOverride, 2200, reason: '拒绝写入不该顺手改掉老值');
      expect(await rowCount(), 1);
    });
  });
}
