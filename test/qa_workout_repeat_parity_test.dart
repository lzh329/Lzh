import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:drift/drift.dart' show Value;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/workout_repeat.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_record_card.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_repeat_button.dart';

import 'fake_database.dart';

/// QA 补充：T-10 / T-15 的**口径一致性**与**非破坏性**。
///
/// 上一轮踩过的坑：训练页历史段写「3/5 组」（完成/总数），记录页写「5 组」，
/// 同一件事两个数。这一轮把历史段删了，但"再练一次"又把组数搬去开练页，
/// 所以必须锁三件事：
///   ① 记录卡上的 N 组 == 重练带到开练页的目标组数总和（同一个数）；
///   ② 卡片文案里不出现 `N/M` 形态；
///   ③ 点「再练一次」只跳路由，**不写库**（原记录一个字节都不能变）。
void main() {
  late AppDatabase db;

  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  WorkoutSetEntity set(int workoutId, int exerciseId, int setNumber) =>
      WorkoutSetEntity(
        id: workoutId * 100 + exerciseId * 10 + setNumber,
        workoutId: workoutId,
        exerciseId: exerciseId,
        setNumber: setNumber,
        reps: 12,
        weightKg: 20,
      );

  WorkoutEntity twoExerciseWorkout() => WorkoutEntity(
        id: 1,
        date: DateTime(2025, 3, 4, 20, 5),
        type: 'free',
        durationSec: 720,
        sets: [
          for (var i = 1; i <= 3; i++) set(1, 1, i),
          for (var i = 1; i <= 3; i++) set(1, 2, i),
        ],
      );

  test('① 记录卡的 N 组 == 重练目标组数之和（6 组 → 3+3）', () {
    final workout = twoExerciseWorkout();
    const names = {1: '深蹲', 2: '平板支撑'};
    const categories = {1: 'strength', 2: 'strength'};

    final slots = WorkoutRepeat.slotsOf(workout, names, categories);
    final totalTarget = slots.fold<int>(0, (a, s) => a + s.targetSets.toInt());

    expect(workout.sets.length, 6, reason: '卡片上写的就是这个数（sets.length）');
    expect(totalTarget, workout.sets.length,
        reason: '两处必须是同一个数：卡片 N 组 == 开练页目标组数合计');
    expect(slots.map((s) => s.targetSets).toList(), [3, 3]);
  });

  testWidgets('② 卡片文案：含「6 组」，不含 N/M 形态', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WorkoutRecordCard(
          workout: twoExerciseWorkout(),
          exerciseNames: const {1: '深蹲', 2: '平板支撑'},
          onTap: () {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.textContaining('6 组'), findsOneWidget);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    for (final t in texts) {
      expect(RegExp(r'\d+\s*/\s*\d+\s*组').hasMatch(t), isFalse,
          reason: '不许出现 N/M 组：$t');
    }
  });

  testWidgets('③ 点「再练一次」只跳 /workout/active，不改动原记录', (tester) async {
    // 把这条记录真的落库，才能验证"没被覆盖"
    final workoutId = await db.into(db.workouts).insert(WorkoutsCompanion.insert(
        date: DateTime(2025, 3, 4, 20, 5),
        type: 'free',
        durationSec: const Value(720)));
    for (var i = 1; i <= 3; i++) {
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            workoutId: workoutId,
            exerciseId: 1,
            setNumber: i,
            reps: const Value(12),
            weightKg: const Value(20),
          ));
    }
    await db.into(db.exercises).insert(
        ExercisesCompanion.insert(name: '深蹲', category: 'strength'));

    final before = await db.select(db.workoutSets).get();
    expect(before, hasLength(3));

    final entity = WorkoutEntity(
      id: workoutId,
      date: DateTime(2025, 3, 4, 20, 5),
      type: 'free',
      durationSec: 720,
      sets: [
        for (final r in before)
          WorkoutSetEntity(
            id: r.id,
            workoutId: r.workoutId,
            exerciseId: r.exerciseId,
            setNumber: r.setNumber,
            reps: r.reps,
            weightKg: r.weightKg,
          ),
      ],
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Scaffold(
            body: Center(child: WorkoutRepeatButton(workout: entity)),
          ),
        ),
        GoRoute(
          path: '/workout/active',
          builder: (_, state) {
            final extra = state.extra;
            final slots =
                extra is List<ExerciseSlot> ? extra : const <ExerciseSlot>[];
            final total =
                slots.fold<int>(0, (a, s) => a + s.targetSets.toInt());
            return Scaffold(
              body: Text('开练 ${slots.length} 个动作 $total 组 '
                  '重量预填=${slots.any((s) => s.targetWeightKg != null)}'),
            );
          },
        ),
      ],
    );

    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pump();

    await tester.tap(find.text('再练一次'));
    await tester.pumpAndSettle();

    // ① 跳到开练页，动作 1 个、目标 3 组、**没有预填重量**
    expect(find.text('开练 1 个动作 3 组 重量预填=false'), findsOneWidget);

    // ② 原记录一个字节都没变：不复制、不覆盖
    final after = await db.select(db.workoutSets).get();
    expect(after, hasLength(3), reason: '再练一次不许复制或覆盖原记录的组');
    expect(after.map((s) => s.setNumber).toList(), [1, 2, 3]);
    expect(after.every((s) => s.weightKg == 20), isTrue);
    expect(after.every((s) => s.reps == 12), isTrue);
    expect(await db.select(db.workouts).get(), hasLength(1),
        reason: '不许顺手新建一条训练');
  });
}
