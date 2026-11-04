import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/ai_tool_router.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

import 'fake_database.dart';

/// 合并工具面的端到端：模型只说 `tool + action`，落库结果必须与旧工具一致
///
/// 走的是真执行器（内部先 normalize 再交给旧 handler），所以这条链路
/// 同时验证了 router 与 handler 的接缝。
void main() {
  late AppDatabase db;
  late AiToolExecutor executor;
  late WorkoutRepositoryImpl workouts;
  late WorkoutTemplateRepositoryImpl templates;

  setUp(() {
    db = fakeDatabase();
    executor = AiToolExecutor(repos: fakeToolRepos(db));
    workouts = WorkoutRepositoryImpl(db);
    templates = WorkoutTemplateRepositoryImpl(db);
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

  Future<int> seedExercise(String name, String category, {int? reps}) =>
      db.into(db.exercises).insert(ExercisesCompanion.insert(
            name: name,
            category: category,
            defaultReps: reps == null ? const Value.absent() : Value(reps),
          ));

  test('① workout:log + template_name → 组次来自模板', () async {
    final squat = await seedExercise('深蹲', 'strength');
    await templates.create(
      name: '腿日',
      difficulty: '入门',
      focus: '全身',
      type: 'strength',
      minutes: 30,
      items: [
        TemplateItemInput(exerciseId: squat, targetSets: 3, targetReps: 12),
      ],
    );

    final r = await run('workout', {
      'action': 'log',
      'template_name': '腿日',
      'minutes': 30,
    });

    final w = await workouts.getById(r['workout_id'] as int);
    expect(w!.sets, hasLength(3));
    expect(w.sets.every((s) => s.exerciseId == squat), isTrue);
    expect(w.sets.every((s) => s.reps == 12), isTrue);
  });

  test('② diet:food → 饮食记录落库', () async {
    final r = await run('diet', {
      'action': 'food',
      'food_name': '牛肉面',
      'grams': 300,
      'calories_per_100g': 200,
    });
    expect(r['ok'], isTrue);
    // 饮食落库 = food_log + food_library（食物名在 library 里）
    final logs = await db.select(db.foodLog).get();
    expect(logs, isNotEmpty);
    final lib = await db.select(db.foodLibrary).get();
    expect(lib.any((f) => f.name == '牛肉面'), isTrue);
  });

  test('③ body:weight → 体重记录落库', () async {
    final r = await run('body', {'action': 'weight', 'weight_jin': 150});
    expect(r['ok'], isTrue);
    final rows = await db.select(db.bodyMetrics).get();
    expect(rows.any((m) => m.weightKg > 70), isTrue);
  });

  test('④ settings:target_weight → 目标体重更新', () async {
    final r = await run('settings', {
      'action': 'target_weight',
      'target_jin': 140,
    });
    expect(r['ok'], isTrue);
    final s = await db.select(db.userSettings).getSingle();
    expect(s.targetWeightKg, closeTo(70, 0.01), reason: '140 斤 = 70 kg');
  });

  test('⑤ template:create → 模板落库且 items 正确', () async {
    final squat = await seedExercise('深蹲', 'strength');
    final r = await run('template', {
      'action': 'create',
      'name': '新模板',
      'difficulty': '入门',
      'focus': '全身',
      'minutes': 20,
      'items': [
        {'exercise_name': '深蹲', 'sets': 4, 'reps': 10},
      ],
    });
    expect(r['ok'], isTrue);

    final all = await templates.getAll();
    final created = all.firstWhere((t) => t.name == '新模板');
    expect(created.items, hasLength(1));
    expect(created.items.single.exerciseName, '深蹲');
    // 用种子库里的「深蹲」或本用例新建的，按名字断言更稳
    expect(created.items.single.targetSets, 4);
    expect(created.items.single.targetReps, 10);
    expect(squat, greaterThan(0));
  });

  test('⑥ body:update_measurement 改数值成功，且**不是**危险操作', () async {
    // 围度记录要求先有体重
    await run('body', {'action': 'weight', 'weight_jin': 150});
    await run('body', {'action': 'measurements', 'waist_cm': 80});
    final rows = await db.select(db.bodyMetrics).get();
    final id = rows.first.id;

    // 危险判定：改数值不该红卡
    expect(isMergedDestructive('body', 'update_measurement'), isFalse);

    final r = await run('body', {
      'action': 'update_measurement',
      'id': id,
      'part': 'waist',
      'value': 79,
    });
    expect(r['ok'], isTrue);
    final after = await db.select(db.bodyMetrics).get();
    expect(after.first.waistCm, closeTo(79, 0.01));
  });

  test('⑦ body:delete_measurement 删除成功，且**是**危险操作', () async {
    await run('body', {'action': 'weight', 'weight_jin': 150});
    await run('body', {'action': 'measurements', 'waist_cm': 82});
    final before = await db.select(db.bodyMetrics).get();
    final id = before.first.id;

    // 危险判定：删围度必须红卡
    expect(isMergedDestructive('body', 'delete_measurement'), isTrue);

    final r = await run('body', {
      'action': 'delete_measurement',
      'id': id,
    });
    expect(r['ok'], isTrue);
    final after = await db.select(db.bodyMetrics).get();
    expect(after.any((m) => m.id == id), isFalse);
  });
}
