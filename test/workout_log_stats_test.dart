import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/plan/data/plan_repository_impl.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/workout_log_draft.dart';

import 'fake_database.dart';

/// 统计口径：**补记进统计（次数/时长/图表），但不算计划完成**。
///
/// `planId` 为 null 天然满足"不算计划完成"，但这条规则必须被**测**住：
/// 以后有人在开练页或统计页加一个 `type == 'plan'` 的过滤，或者把补记也写成
/// `planId`，这条测试要立刻红。
void main() {
  late AppDatabase db;
  late WorkoutRepository workoutRepo;
  late PlanRepository planRepo;
  late int exerciseId;

  setUp(() async {
    db = fakeDatabase();
    workoutRepo = WorkoutRepositoryImpl(db);
    planRepo = PlanRepositoryImpl(db);
    exerciseId = await db.into(db.exercises).insert(
        ExercisesCompanion.insert(name: '深蹲', category: 'strength'));
  });

  tearDown(() async {
    await db.close();
  });

  /// 用「记一笔」的同一套草稿逻辑落一条补记（与页面保存路径一致）
  Future<int> saveLogEntry({int sets = 3}) async {
    const draft = WorkoutLogDraft();
    final entry = WorkoutLogEntry(
      exerciseId: exerciseId,
      exerciseName: '深蹲',
      category: 'strength',
      sets: sets,
      reps: 12,
    );
    final filled = draft.add(entry);
    final workout = await workoutRepo.createWorkout(
      date: DateTime.now(),
      type: WorkoutLogDraft.workoutType,
      planId: null,
      sets: filled.toSets(),
    );
    return workout.id;
  }

  test('补记进统计：getAll 从 1 条变 2 条（统计页的数据源就是它）', () async {
    // 今天已经按计划练过一次
    final plan = await planRepo.create('减脂计划');
    await planRepo.saveDays(plan.id, [
      PlanDayInput(
        dayOfWeek: DateTime.now().weekday,
        exerciseId: exerciseId,
        targetSets: 3,
        targetReps: 10,
      ),
    ]);
    await planRepo.toggleActive(plan.id, true);
    await workoutRepo.createWorkout(
      date: DateTime.now(),
      type: 'plan',
      planId: plan.id,
      durationSec: 900,
      sets: [
        const NewSetData(exerciseId: 1, setNumber: 1, reps: 10),
      ],
    );

    final before = await workoutRepo.getAll();
    expect(before, hasLength(1));

    await saveLogEntry();

    final after = await workoutRepo.getAll();
    expect(after, hasLength(2), reason: '统计次数 +1');
    // 统计页按 getAll 全量算（不按 type 过滤），时长/图表也一视同仁
    final totalMinutes = after.fold<int>(
        0, (sum, w) => sum + (w.durationSec == null ? 0 : w.durationSec! ~/ 60));
    expect(totalMinutes, 15, reason: '补记没有计时 ⇒ 只算已有时长');
  });

  test('补记**不算**计划完成：按 planId 统计的当日计划完成数不变', () async {
    final plan = await planRepo.create('减脂计划');
    await planRepo.toggleActive(plan.id, true);
    await workoutRepo.createWorkout(
      date: DateTime.now(),
      type: 'plan',
      planId: plan.id,
      durationSec: 600,
      sets: [const NewSetData(exerciseId: 1, setNumber: 1, reps: 10)],
    );

    Future<int> planDoneToday() async {
      final all = await workoutRepo.getAll();
      final today = DateTime.now();
      return all
          .where((w) =>
              w.planId == plan.id &&
              w.date.year == today.year &&
              w.date.month == today.month &&
              w.date.day == today.day)
          .length;
    }

    expect(await planDoneToday(), 1, reason: '计划内训练：1 次');

    await saveLogEntry();

    expect(await planDoneToday(), 1,
        reason: '补记 planId 为 null ⇒ 不许让计划完成度 +1');
    // 但它在总训练次数里（统计口径）
    expect(await workoutRepo.getAll(), hasLength(2));
  });

  test('补记算"今天练过"（今日打卡的完成训练项）', () async {
    await saveLogEntry();

    final container =
        ProviderContainer(overrides: [databaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);

    final data = await container.read(dashboardDataProvider.future);
    final today = DateTime.now();
    final todayWorkouts = data.allWorkouts
        .where((w) =>
            w.date.year == today.year &&
            w.date.month == today.month &&
            w.date.day == today.day)
        .toList();

    expect(todayWorkouts, hasLength(1),
        reason: '补记也是"今天练了"，今日打卡该亮');
  });

  test('源码守卫：统计页不按 type 过滤（否则补记会被漏掉）', () {
    final src = File(
            'lib/features/workout/presentation/pages/workout_stats_page.dart')
        .readAsStringSync();
    expect(src.contains("type == 'plan'"), isFalse);
    expect(src.contains("type == 'free'"), isFalse);
    expect(src.contains('w.type'), isFalse,
        reason: '统计口径是"全部训练"，不区分计划内/即时/补记');
  });

  test('补记的来源字段与用户向文案（卡片徽标/详情页标签都读它）', () {
    expect(WorkoutLogDraft.workoutType, 'log', reason: '内部值');
    expect(WorkoutLogDraft.typeLabel, '补记', reason: '用户向文案');
  });
}
