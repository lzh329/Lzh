import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_admin_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_readers.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

import 'fake_database.dart';

/// 给嘎教练的训练记录「增删改查」工具（log_workout 带动作 / query_workouts /
/// update_workout / delete_workout）的行为回归。
void main() {
  late AppDatabase db;
  late AiToolWriters writers;
  late AiToolReaders readers;
  late AiToolAdminWriters admins;

  setUp(() async {
    db = fakeDatabase();
    final repos = fakeToolRepos(db);
    writers = AiToolWriters(repos);
    readers = AiToolReaders(repos);
    admins = AiToolAdminWriters(repos);
    await db.into(db.exercises).insert(
        ExercisesCompanion.insert(name: '深蹲', category: 'gym'));
  });

  tearDown(() async => db.close());

  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> args) async {
    final exec = switch (name) {
      AiToolSpecs.logWorkout => writers,
      AiToolSpecs.updateWorkout => writers,
      AiToolSpecs.queryWorkouts => readers,
      AiToolSpecs.deleteWorkout => admins,
      _ => throw ArgumentError(name),
    };
    return jsonDecode(await exec.execute(AiToolCall(
      id: 'call-1',
      name: name,
      argumentsJson: jsonEncode(args),
    ))) as Map<String, dynamic>;
  }

  group('参数解析', () {
    test('workoutExercises：解析动作、组数默认 1、次数重量校验', () {
      final list = AiToolArgs.workoutExercises({
        'exercises': [
          {'name': '深蹲', 'sets': 4, 'reps': 12, 'weight_kg': 60},
          {'name': '平板支撑'},
          {'name': '', 'sets': 3}, // 空名丢弃
          {'sets': 3}, // 无名丢弃
        ],
      });
      expect(list, hasLength(2));
      expect(list[0].name, '深蹲');
      expect(list[0].sets, 4);
      expect(list[0].reps, 12);
      expect(list[0].weightKg, 60);
      expect(list[1].name, '平板支撑');
      expect(list[1].sets, 1, reason: '组数缺省为 1');
    });

    test('workoutId / workoutCount：非法输入', () {
      expect(AiToolArgs.workoutId({'workout_id': 3}), 3);
      expect(() => AiToolArgs.workoutId({}), throwsA(isA<AiToolException>()));
      expect(AiToolArgs.workoutCount({}), 7);
      expect(AiToolArgs.workoutCount({'count': 99}), 20, reason: '上限 20');
      expect(AiToolArgs.workoutCount({'count': 0}), 1, reason: '下限 1');
    });
  });

  group('增删改查', () {
    test('log_workout 带动作 → 落库成 workout + 按组展开的 sets', () async {
      final res = await call(AiToolSpecs.logWorkout, {
        'workout_type': '力量',
        'minutes': 45,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12, 'weight_kg': 60},
        ],
      });
      expect(res['ok'], true);
      expect(res['exercise_count'], 1);
      expect(res['workout_id'], isA<int>(), reason: '回执带 workout_id，芯片据此跳详情');

      final workouts = await db.select(db.workouts).get();
      expect(workouts, hasLength(1));
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(3), reason: '3 组 = 3 条 set');
      expect(sets.map((s) => s.setNumber).toList()..sort(), [1, 2, 3]);
      expect(sets.every((s) => s.reps == 12), isTrue);
      expect(sets.every((s) => s.weightKg == 60), isTrue);
    });

    test('log_workout 动作名不在库 → 报错且不落库', () async {
      await expectLater(
        call(AiToolSpecs.logWorkout, {
          'workout_type': '力量',
          'minutes': 30,
          'exercises': [
            {'name': '不存在的动作', 'sets': 3},
          ],
        }),
        throwsA(isA<AiToolException>()),
      );
      expect(await db.select(db.workouts).get(), isEmpty);
    });

    test('query_workouts → 返回明细（含动作名与组次重）', () async {
      await call(AiToolSpecs.logWorkout, {
        'workout_type': '力量',
        'minutes': 45,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12, 'weight_kg': 60},
        ],
      });
      final res = await call(AiToolSpecs.queryWorkouts, {'count': 5});
      final workouts = res['workouts'] as List;
      expect(workouts, hasLength(1));
      final w = workouts.first as Map;
      expect(w['id'], isA<int>());
      final exs = w['exercises'] as List;
      expect(exs, hasLength(1));
      expect((exs.first as Map)['name'], '深蹲');
      expect((exs.first as Map)['sets'], 3);
      expect((exs.first as Map)['weight_kg'], 60);
    });

    test('update_workout → 整体替换动作清单', () async {
      await call(AiToolSpecs.logWorkout, {
        'workout_type': '力量',
        'minutes': 45,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12},
        ],
      });
      final rows = await db.select(db.workouts).get();
      final id = rows.single.id;

      final res = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'exercises': [
          {'name': '深蹲', 'sets': 5, 'reps': 8},
        ],
      });
      expect(res['ok'], true);
      expect(res['exercise_count'], 1);

      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(5), reason: '旧 3 组被替换成新 5 组');
      expect(sets.every((s) => s.reps == 8), isTrue);
    });

    test('delete_workout → 按 id 删除（连同 sets 级联）', () async {
      await call(AiToolSpecs.logWorkout, {
        'workout_type': '力量',
        'minutes': 45,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12},
        ],
      });
      final rows = await db.select(db.workouts).get();
      final id = rows.single.id;

      final res = await call(AiToolSpecs.deleteWorkout, {'workout_id': id});
      expect(res['ok'], true);
      expect(await db.select(db.workouts).get(), isEmpty);
      expect(await db.select(db.workoutSets).get(), isEmpty);
    });
  });
}
