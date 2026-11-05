import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';

import 'fake_database.dart';

/// 计时类动作的秒级时长 + 模板动作上限
void main() {
  late AppDatabase db;
  late AiToolExecutor executor;
  late WorkoutRepositoryImpl workouts;

  setUp(() {
    db = fakeDatabase();
    executor = AiToolExecutor(repos: fakeToolRepos(db));
    workouts = WorkoutRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<Map<String, dynamic>> run(
      String tool, Map<String, dynamic> args) async {
    final out = await executor.execute(AiToolCall(
      id: 'c1',
      name: tool,
      argumentsJson: jsonEncode(args),
    ));
    return jsonDecode(out) as Map<String, dynamic>;
  }

  Future<int> seed(String name, String category) =>
      db.into(db.exercises).insert(
          ExercisesCompanion.insert(name: name, category: category));

  group('workout:log 的秒级时长', () {
    test('① seconds=30 → 落库 durationSec=30、reps=null', () async {
      final plank = await seed('平板支撑', 'strength');
      final r = await run('workout', {
        'action': 'log',
        'workout_type': '力量',
        'minutes': 10,
        'exercises': [
          {'name': '平板支撑', 'sets': 2, 'seconds': 30},
        ],
      });

      final w = await workouts.getById(r['workout_id'] as int);
      expect(w!.sets, hasLength(2));
      expect(w.sets.every((s) => s.exerciseId == plank), isTrue);
      expect(w.sets.every((s) => s.durationSec == 30), isTrue);
      expect(w.sets.every((s) => s.reps == null), isTrue);
    });

    test('② minutes=0.5 等价 30 秒', () async {
      await seed('平板支撑', 'strength');
      final r = await run('workout', {
        'action': 'log',
        'workout_type': '力量',
        'minutes': 10,
        'exercises': [
          {'name': '平板支撑', 'sets': 1, 'minutes': 0.5},
        ],
      });
      final w = await workouts.getById(r['workout_id'] as int);
      expect(w!.sets.single.durationSec, 30);
    });

    test('③ 同时给 seconds 与 minutes → 以 seconds 为准', () async {
      await seed('平板支撑', 'strength');
      final r = await run('workout', {
        'action': 'log',
        'workout_type': '力量',
        'minutes': 10,
        'exercises': [
          {'name': '平板支撑', 'sets': 1, 'seconds': 45, 'minutes': 5},
        ],
      });
      final w = await workouts.getById(r['workout_id'] as int);
      expect(w!.sets.single.durationSec, 45, reason: 'seconds 优先级更高');
    });
  });

  group('模板动作上限 1~40', () {
    test('40 个动作可以建', () async {
      await seed('深蹲', 'strength');
      final items = [
        for (var i = 0; i < 40; i++)
          {'exercise_name': '深蹲', 'sets': 1, 'reps': 10},
      ];
      final r = await run('template', {
        'action': 'create',
        'name': '40 项模板',
        'minutes': 30,
        'items': items,
      });
      expect(r['ok'], isTrue);
    });

    test('41 个动作被拒绝，且是 ok:false 回执（不静默截断）', () async {
      await seed('深蹲', 'strength');
      final items = [
        for (var i = 0; i < 41; i++)
          {'exercise_name': '深蹲', 'sets': 1, 'reps': 10},
      ];
      try {
        await run('template', {
          'action': 'create',
          'name': '41 项模板',
          'minutes': 30,
          'items': items,
        });
        fail('41 个动作必须被拒绝');
      } on AiToolException catch (e) {
        expect(e.message, contains('40'));
      }
      // 没有落库（真拒绝，不是截断后建一半）
      final all = await db.select(db.workoutTemplates).get();
      expect(all.any((t) => t.name == '41 项模板'), isFalse);
    });
  });
}
