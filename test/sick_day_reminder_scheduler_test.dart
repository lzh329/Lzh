import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/services/reminder_scheduler.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

/// 记录调用的假落点：本地通知插件在单测进程里不可用，没有这层就断言不了
/// "今天没排"。
class _FakeSink implements ReminderSink {
  final workoutSlots = <int>[];
  final weighInIds = <int>[];
  final cancelledIds = <int>[];
  int cancelAllCount = 0;

  @override
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) async {
    workoutSlots.add(dayOfWeek);
  }

  @override
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) async {
    weighInIds.add(id);
  }

  @override
  Future<void> cancelById(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }
}

/// 一周七天的槽位（无活跃计划时的形态：每天一条「每日训练」）
List<WorkoutReminderSlot> _allWeekSlots() => [
      for (int d = 0; d < 7; d++)
        WorkoutReminderSlot(
          id: d,
          planName: '每日训练',
          dayLabel: '',
          dayOfWeek: d,
        ),
    ];

void main() {
  late AppDatabase db;
  late DailyOverrideRepository repo;
  late _FakeSink sink;
  late ReminderScheduler scheduler;

  // 2025-03-04 是周二 → weekday % 7 == 2
  final tuesday = DateTime(2025, 3, 4);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = DailyOverrideRepository(db);
    sink = _FakeSink();
    scheduler = ReminderScheduler(
      sink: sink,
      gate: SickDayGate(repo, UserSettingsRepositoryImpl(db)),
      now: () => tuesday,
    );
  });

  tearDown(() async => db.close());

  Future<void> seedOverride({required bool reminderPaused}) async {
    await repo.upsert(
      date: tuesday,
      setsScale: 0.5,
      reminderPaused: reminderPaused,
      source: 'user',
    );
  }

  Future<void> reschedule({bool enabled = true}) {
    return scheduler.reschedule(
      enabled: enabled,
      hour: 8,
      minute: 0,
      workoutSlots: _allWeekSlots(),
      weighInId: kWeighInReminderId,
    );
  }

  group('T03-D1 / D2 今天暂停 → 不排', () {
    test('生效 + reminderPaused=true → 训练提醒不排今天那条', () async {
      await seedOverride(reminderPaused: true);

      await reschedule();

      expect(sink.workoutSlots, isNot(contains(2)), reason: '今天（周二）这条不许排');
      expect(sink.workoutSlots, hasLength(6), reason: '其余 6 天照排');
    });

    test('生效 + reminderPaused=true → 称重提醒当天也不排', () async {
      await seedOverride(reminderPaused: true);

      await reschedule();

      expect(sink.weighInIds, isEmpty, reason: '称重提醒每天重复，今天被暂停就只能整条不排');
    });

    test('pausedToday 判定：覆盖存在但 reminderPaused=false → 不暂停', () async {
      await seedOverride(reminderPaused: false);

      expect(await scheduler.pausedToday(), isFalse);
    });

    test('pausedToday 判定：当天有覆盖且 reminderPaused=true → 暂停', () async {
      await seedOverride(reminderPaused: true);

      expect(await scheduler.pausedToday(), isTrue);
    });
  });

  group('T03-D3 reminderPaused=false / 非生效日 → 照常排', () {
    test('覆盖存在但 reminderPaused=false → 7 条训练提醒 + 7 条称重提醒全排', () async {
      await seedOverride(reminderPaused: false);

      await reschedule();

      expect(sink.workoutSlots, [0, 1, 2, 3, 4, 5, 6]);
      expect(sink.weighInIds, [kWeighInReminderId]);
    });

    test('当天没有覆盖 → 照常排（口径只认今天）', () async {
      await reschedule();

      expect(sink.workoutSlots, [0, 1, 2, 3, 4, 5, 6]);
      expect(sink.weighInIds, [kWeighInReminderId]);
    });

    test('昨天的覆盖不影响今天', () async {
      await repo.upsert(
        date: tuesday.subtract(const Duration(days: 1)),
        setsScale: 0.5,
        reminderPaused: true,
        source: 'user',
      );

      await reschedule();

      expect(sink.workoutSlots, hasLength(7), reason: '昨天生病不是今天生病');
    });
  });

  group('T03-D6 全局开关', () {
    test('enabled=false → 一条都不排', () async {
      await seedOverride(reminderPaused: true);

      await reschedule(enabled: false);

      expect(sink.workoutSlots, isEmpty);
      expect(sink.weighInIds, isEmpty);
      expect(sink.cancelAllCount, 1, reason: '关掉开关要把旧的清干净');
    });
  });

  group('T03-D1 纯函数', () {
    test('只有今天返回跳过，其余 6 天都不跳', () {
      for (int d = 0; d < 7; d++) {
        expect(
          skipsWorkoutReminderToday(
            now: tuesday,
            dayOfWeek: d,
            pausedToday: true,
          ),
          d == 2,
          reason: 'd=$d 只该在周二（2）被跳过',
        );
      }
    });

    test('pausedToday=false → 一天都不跳', () {
      for (int d = 0; d < 7; d++) {
        expect(
          skipsWorkoutReminderToday(
            now: tuesday,
            dayOfWeek: d,
            pausedToday: false,
          ),
          isFalse,
        );
      }
    });
  });

  group('T03-D7 不改全局提醒设置', () {
    test('排期前后 UserSettings 的提醒三列不变', () async {
      final settingsRepo = UserSettingsRepositoryImpl(db);
      await settingsRepo.save(
        reminderEnabled: true,
        reminderHour: 8,
        reminderMinute: 0,
      );

      await seedOverride(reminderPaused: true);
      await reschedule();

      final s = await settingsRepo.get();
      expect(s!.reminderEnabled, isTrue, reason: '生病模式只是今天不响，不改用户设置');
      expect(s.reminderHour, 8);
      expect(s.reminderMinute, 0);
    });
  });

  group('buildWorkoutSlots（启动排期与设置页共用同一份推导）', () {
    test('没有活跃计划 → 7 条「每日训练」，id 与训练提醒的 0 段一致', () {
      final slots = buildWorkoutSlots(const <PlanEntity>[]);

      expect(slots.map((s) => s.dayOfWeek), [0, 1, 2, 3, 4, 5, 6]);
      expect(slots.map((s) => s.id), [0, 1, 2, 3, 4, 5, 6]);
      expect(slots.first.planName, '每日训练');
    });

    test('有活跃计划 → 只推导活跃计划里的天，非活跃计划不参与', () {
      final slots = buildWorkoutSlots(<PlanEntity>[
        const PlanEntity(
          id: 1,
          name: '增肌计划',
          isActive: true,
          days: [
            PlanDayEntity(
              id: 1,
              planId: 1,
              dayOfWeek: 1,
              exerciseId: 1,
              targetSets: 4,
            ),
            PlanDayEntity(
              id: 2,
              planId: 1,
              dayOfWeek: 3,
              exerciseId: 2,
              targetSets: 3,
            ),
          ],
        ),
        const PlanEntity(
          id: 2,
          name: '旧计划',
          isActive: false,
          days: [
            PlanDayEntity(
              id: 3,
              planId: 2,
              dayOfWeek: 5,
              exerciseId: 3,
              targetSets: 5,
            ),
          ],
        ),
      ]);

      expect(slots.map((s) => s.dayOfWeek), [1, 3]);
      expect(slots.map((s) => s.dayLabel), ['周一', '周三']);
      expect(slots.map((s) => s.planName), ['增肌计划', '增肌计划']);
      expect(slots.map((s) => s.id), [0, 1]);
    });
  });

  group('T03-D5 跨天自动恢复', () {
    test('跨天后重排 → 被跳过的那条自己回来', () async {
      await seedOverride(reminderPaused: true);

      // 周三（3）重排：覆盖只存在于周二，周二的提醒要回来
      final wednesdayScheduler = ReminderScheduler(
        sink: sink,
        gate: SickDayGate(repo, UserSettingsRepositoryImpl(db)),
        now: () => tuesday.add(const Duration(days: 1)),
      );
      await wednesdayScheduler.reschedule(
        enabled: true,
        hour: 8,
        minute: 0,
        workoutSlots: _allWeekSlots(),
        weighInId: kWeighInReminderId,
      );

      expect(sink.workoutSlots, contains(2), reason: '周二那条跨天后要恢复');
      expect(sink.workoutSlots, [0, 1, 2, 3, 4, 5, 6]);
    });
  });
}
