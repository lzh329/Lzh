import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/diet/presentation/pages/diet_page.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    // 饮食页要用 zh_CN 的日期格式，不初始化 intl 会抛 LocaleDataException。
    try {
      await initializeDateFormatting('zh_CN');
    } catch (_) {
      // 测试环境拿不到资源包时按 en 兜底，不影响本节断言的目标（热量口径）
    }
  });

  tearDown(() async => db.close());

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> seedOverride({
    double? setsScale,
    int? calorieTargetOverride,
    bool reminderPaused = false,
  }) {
    return DailyOverrideRepository(db).upsert(
      date: DateTime.now(),
      setsScale: setsScale,
      calorieTargetOverride: calorieTargetOverride,
      reminderPaused: reminderPaused,
      source: 'user',
    );
  }

  Widget buildHost(ProviderContainer container, Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: child),
    );
  }

  group('T03-B1 饮食页把今日热量目标接到了闸门上', () {
    testWidgets('有覆盖（放宽）→ 显示覆盖值', (WidgetTester tester) async {
      await UserSettingsRepositoryImpl(db).save(dailyCalorieTarget: 2000);
      await seedOverride(calorieTargetOverride: 2200);

      final container = buildContainer();
      await tester.pumpWidget(buildHost(container, const DietPage()));
      await tester.pumpAndSettle();

      expect(find.text('/ 2200 kcal'), findsOneWidget,
          reason: '页面真的读的是「今日口径」，不是直接读 userSettings');
      expect(find.text('/ 2000 kcal'), findsNothing);
    });

    testWidgets('T03-B2 覆盖存在但没有热量字段 → 回落全局值', (WidgetTester tester) async {
      await UserSettingsRepositoryImpl(db).save(dailyCalorieTarget: 2000);
      await seedOverride(setsScale: 0.5);

      final container = buildContainer();
      await tester.pumpWidget(buildHost(container, const DietPage()));
      await tester.pumpAndSettle();

      expect(find.text('/ 2000 kcal'), findsOneWidget);
    });

    testWidgets('T03-B3 全局目标为 null → 不显示 0，也不显示目标',
        (WidgetTester tester) async {
      await seedOverride(calorieTargetOverride: 2200);

      final container = buildContainer();
      await tester.pumpWidget(buildHost(container, const DietPage()));
      await tester.pumpAndSettle();

      expect(find.text('/ 0 kcal'), findsNothing,
          reason: 'null = 没设目标，绝不能兜成 0 —— 0 会被读成「目标就是 0 千卡」');
      expect(find.text('kcal'), findsOneWidget);
    });
  });

  group('T03-B4 训练会话把今日组数接到了闸门上', () {
    List<ExerciseSlot> squats() => const [
          ExerciseSlot(
            exerciseId: 1,
            exerciseName: '深蹲',
            category: 'gym',
            targetSets: 4,
          ),
        ];

    test('有覆盖（0.5）→ 4 组变 2 组，动作名照常显示', () async {
      await seedOverride(setsScale: 0.5, reminderPaused: true);

      final container = buildContainer();
      final notifier = container.read(workoutSessionProvider.notifier);
      await notifier.initFree(squats());

      final slots = container.read(workoutSessionProvider).slots;
      expect(slots, hasLength(1));
      expect(slots.single.targetSets, 2);
      expect(slots.single.exerciseName, '深蹲', reason: '缩的是执行值，不是把计划藏起来');
    });

    test('没有覆盖 → 组数原样', () async {
      final container = buildContainer();
      final notifier = container.read(workoutSessionProvider.notifier);
      await notifier.initFree(squats());

      expect(container.read(workoutSessionProvider).slots.single.targetSets, 4);
    });

    test('极端系数（0.1）也不会缩成 0 组', () async {
      await seedOverride(setsScale: 0.1);

      final container = buildContainer();
      final notifier = container.read(workoutSessionProvider.notifier);
      await notifier.initFree(squats());

      expect(container.read(workoutSessionProvider).slots.single.targetSets, 1,
          reason: '下限 1 组是硬规定：0 组等于把计划抹掉');
    });

    test('今天的组数改动不会被后续改时长再缩一次', () async {
      await seedOverride(setsScale: 0.5);

      final container = buildContainer();
      final notifier = container.read(workoutSessionProvider.notifier);
      await notifier.initFree(squats());
      notifier.setCurrentSlotDurationSec(45);

      expect(
        container.read(workoutSessionProvider).slots.single.targetSets,
        2,
        reason: 'setCurrentSlotDurationSec 只是复制当前槽位改时长，不能再缩放一次',
      );
    });
  });
}
