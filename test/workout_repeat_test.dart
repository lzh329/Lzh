import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/workout_repeat.dart';

/// T-15 「再练一次」：带动作/组数/次数，**绝不带重量**
void main() {
  WorkoutEntity workout(List<WorkoutSetEntity> sets) => WorkoutEntity(
        id: 7,
        date: DateTime(2025, 3, 4, 20),
        type: 'free',
        durationSec: 900,
        sets: sets,
      );

  WorkoutSetEntity set(int exerciseId, int setNumber,
          {int? reps, int? durationSec, double? weightKg}) =>
      WorkoutSetEntity(
        id: setNumber,
        workoutId: 7,
        exerciseId: exerciseId,
        setNumber: setNumber,
        reps: reps,
        durationSec: durationSec,
        weightKg: weightKg,
      );

  const names = {1: '深蹲', 2: '平板支撑'};
  const categories = {1: 'strength', 2: 'strength'};

  test('按动作分组：5 个动作 12 组 → 5 个 slot，组数与记录一致', () {
    final entity = workout([
      for (var i = 1; i <= 3; i++) set(1, i, reps: 12, weightKg: 40),
      for (var i = 4; i <= 5; i++) set(2, i, durationSec: 30),
    ]);

    final slots = WorkoutRepeat.slotsOf(entity, names, categories);

    expect(slots, hasLength(2));
    expect(slots.first.exerciseId, 1);
    expect(slots.first.exerciseName, '深蹲');
    expect(slots.first.category, 'strength');
    expect(slots.first.targetSets, 3);
    expect(slots.first.targetReps, 12);
    expect(slots.first.targetWeightKg, isNull, reason: 'T15：绝不预填重量');

    expect(slots.last.exerciseId, 2);
    expect(slots.last.targetDurationSec, 30);
    expect(slots.last.targetWeightKg, isNull);
  });

  test('组数 = 该动作出现过的组数，不是整条记录的组数', () {
    final entity = workout([
      set(1, 1, reps: 10),
      set(1, 2, reps: 10),
      set(2, 3, durationSec: 60),
    ]);
    final slots = WorkoutRepeat.slotsOf(entity, names, categories);
    expect(slots.map((s) => s.targetSets).toList(), [2, 1]);
  });

  test('次数取众数；并列取较大值（宁可多做一个，也不要少做）', () {
    final entity = workout([
      set(1, 1, reps: 8),
      set(1, 2, reps: 12),
      set(1, 3, reps: 8),
      set(1, 4, reps: 12),
    ]);
    final slots = WorkoutRepeat.slotsOf(entity, names, categories);
    expect(slots.single.targetReps, 12, reason: '8 和 12 各两次 → 取较大值');
  });

  test('没有次数也没有时长（纯自重空记录）：两个字段都 null，不崩', () {
    final entity = workout([set(1, 1), set(1, 2)]);
    final slots = WorkoutRepeat.slotsOf(entity, names, categories);
    expect(slots.single.targetReps, isNull);
    expect(slots.single.targetDurationSec, isNull);
    expect(slots.single.targetSets, 2);
  });

  test('动作已被删除（名字/分类查不到）：用兜底值，仍然可重练', () {
    final entity = workout([set(99, 1, reps: 10)]);
    final slots = WorkoutRepeat.slotsOf(entity, const {}, const {});
    expect(slots.single.exerciseId, 99);
    expect(slots.single.exerciseName, '动作');
    expect(slots.single.category, 'strength');
  });

  test('没有任何 sets → 空列表（调用方据此置灰按钮）', () {
    final entity = workout(const []);
    expect(WorkoutRepeat.slotsOf(entity, names, categories), isEmpty);
  });

  test('保持动作首次出现的顺序（用户上次的练法顺序值得保留）', () {
    final entity = workout([
      set(2, 1, durationSec: 30),
      set(1, 2, reps: 10),
      set(2, 3, durationSec: 30),
    ]);
    final slots = WorkoutRepeat.slotsOf(entity, names, categories);
    expect(slots.map((s) => s.exerciseId).toList(), [2, 1]);
  });

  test('重量字段永远不被赋值（逐字段断言，防止将来"顺手填一下"）', () {
    final entity = workout([
      set(1, 1, reps: 10, weightKg: 60),
      set(1, 2, reps: 10, weightKg: 60),
    ]);
    for (final slot in WorkoutRepeat.slotsOf(entity, names, categories)) {
      expect(slot.targetWeightKg, isNull);
    }
  });
}
