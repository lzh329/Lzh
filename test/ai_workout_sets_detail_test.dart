import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

import 'fake_database.dart';

/// 补记训练后，每一组的「次数 / 时长」必须真的落库
///
/// 真机：教练补记的训练，详情页每组都显示"未记录" —— 因为
/// ① 力量动作模型没传 reps 时没回落动作库默认值
/// ② 有氧根本没有"每组时长"参数可填
void main() {
  late AppDatabase db;
  late AiToolWriters writers;
  late WorkoutRepositoryImpl workouts;

  setUp(() async {
    db = fakeDatabase();
    writers = AiToolWriters(fakeToolRepos(db));
    workouts = WorkoutRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<Map<String, dynamic>> logWorkout(Map<String, dynamic> args) async {
    return jsonDecode(await writers.execute(AiToolCall(
      id: 'c1',
      name: AiToolSpecs.logWorkout,
      argumentsJson: jsonEncode(args),
    ))) as Map<String, dynamic>;
  }

  Future<WorkoutEntity> readSets(int workoutId) async {
    final w = await workouts.getById(workoutId);
    return w!;
  }

  test('① 力量动作传 reps=12 → 4 组都写 reps=12、durationSec=null', () async {
    await db
        .into(db.exercises)
        .insert(ExercisesCompanion.insert(name: '深蹲', category: 'strength'));

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 30,
      'exercises': [
        {'name': '深蹲', 'sets': 4, 'reps': 12},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    expect(detail.sets, hasLength(4));
    for (final s in detail.sets) {
      expect(s.reps, 12);
      expect(s.durationSec, isNull);
    }
  });

  test('② 力量动作不传 reps、动作库有 defaultReps=15 → 用默认值', () async {
    await db.into(db.exercises).insert(ExercisesCompanion.insert(
          name: '俯卧撑',
          category: 'strength',
          defaultReps: const Value(15),
        ));

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 20,
      'exercises': [
        {'name': '俯卧撑', 'sets': 3},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    for (final s in detail.sets) {
      expect(s.reps, 15, reason: '应回落到动作库默认次数');
    }
  });

  test('③ 力量动作不传 reps、动作库也无默认 → reps=null（诚实兜底）', () async {
    await db
        .into(db.exercises)
        .insert(ExercisesCompanion.insert(name: '哑铃弯举', category: 'strength'));

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 15,
      'exercises': [
        {'name': '哑铃弯举', 'sets': 2},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    for (final s in detail.sets) {
      expect(s.reps, isNull, reason: '不瞎编次数');
    }
  });

  test('④ 有氧动作传 minutes=30 → sets=1、durationSec=1800', () async {
    await db
        .into(db.exercises)
        .insert(ExercisesCompanion.insert(name: '跑步', category: 'cardio'));

    final r = await logWorkout({
      'workout_type': '有氧',
      'minutes': 30,
      'exercises': [
        {'name': '跑步', 'sets': 1, 'minutes': 30},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    expect(detail.sets, hasLength(1));
    expect(detail.sets.single.durationSec, 1800);
    expect(detail.sets.single.reps, isNull);
  });

  test('⑤ 有氧动作不传 minutes、动作库无默认 → durationSec=null', () async {
    await db
        .into(db.exercises)
        .insert(ExercisesCompanion.insert(name: '椭圆机', category: 'cardio'));

    final r = await logWorkout({
      'workout_type': '有氧',
      'minutes': 25,
      'exercises': [
        {'name': '椭圆机', 'sets': 1},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    expect(detail.sets.single.durationSec, isNull);
  });

  test('⑥ 拉伸动作传 minutes=0.75 → durationSec=45（小数分钟四舍五入）', () async {
    await db
        .into(db.exercises)
        .insert(ExercisesCompanion.insert(name: '肩背拉伸', category: 'stretch'));

    final r = await logWorkout({
      'workout_type': '拉伸',
      'minutes': 10,
      'exercises': [
        {'name': '肩背拉伸', 'sets': 2, 'minutes': 0.75},
      ],
    });

    final detail = await readSets(r['workout_id'] as int);
    expect(detail.sets, hasLength(2));
    for (final s in detail.sets) {
      expect(s.durationSec, 45);
    }
  });

  test('⑦ schema 守卫：logWorkout 的 exercises.items 里有 minutes 字段', () {
    final def = AiToolSpecs.defs.firstWhere(
        (d) => (d['function'] as Map)['name'] == AiToolSpecs.logWorkout);
    final items =
        ((def['function'] as Map)['parameters'] as Map)['properties'] as Map;
    final exerciseProps =
        ((items['exercises'] as Map)['items'] as Map)['properties'] as Map;
    expect(exerciseProps.containsKey('minutes'), isTrue,
        reason: '有氧每组时长靠这个字段，删了补记就永远填不上');
    expect(exerciseProps.containsKey('reps'), isTrue);
  });
}
