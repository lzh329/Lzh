import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/data/workout_repository_impl.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/domain/template_expansion.dart';

import 'fake_database.dart';

/// 「用模板补记」：组次/时长必须原样来自模板
///
/// 真机：用户说「补一个 11/02 的 XX 模板记录」，模型把模板口述成 exercises，
/// 翻译过程丢了 targetReps/targetDurationSec → 详情页每组"未记录"。
void main() {
  late AppDatabase db;
  late AiToolWriters writers;
  late WorkoutRepositoryImpl workouts;
  late WorkoutTemplateRepositoryImpl templates;

  setUp(() {
    db = fakeDatabase();
    writers = AiToolWriters(fakeToolRepos(db));
    workouts = WorkoutRepositoryImpl(db);
    templates = WorkoutTemplateRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<int> seedExercise(String name, String category, {int? defaultReps}) =>
      db.into(db.exercises).insert(ExercisesCompanion.insert(
            name: name,
            category: category,
            defaultReps: Value(defaultReps),
          ));

  Future<int> seedTemplate({
    required String name,
    required String type,
    required int minutes,
    required List<TemplateItemInput> items,
  }) =>
      templates.create(
        name: name,
        difficulty: '入门',
        focus: '全身',
        type: type,
        minutes: minutes,
        items: items,
      );

  Future<Map<String, dynamic>> logWorkout(Map<String, dynamic> args) async {
    return jsonDecode(await writers.execute(AiToolCall(
      id: 'c1',
      name: 'log_workout',
      argumentsJson: jsonEncode(args),
    ))) as Map<String, dynamic>;
  }

  Future<WorkoutEntity> detail(int id) async => (await workouts.getById(id))!;

  test('① 力量模板（深蹲 4×12 + 卧推 3×10）→ set_count=7，每组 reps 与模板一致',
      () async {
    final squat = await seedExercise('深蹲', 'strength');
    final bench = await seedExercise('卧推', 'strength');
    await seedTemplate(
      name: '胸腿日',
      type: 'strength',
      minutes: 40,
      items: [
        TemplateItemInput(
            exerciseId: squat, targetSets: 4, targetReps: 12),
        TemplateItemInput(
            exerciseId: bench, targetSets: 3, targetReps: 10),
      ],
    );

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 40,
      'template_name': '胸腿日',
    });

    expect(r['set_count'], 7);
    final d = await detail(r['workout_id'] as int);
    final reps = d.sets
        .where((s) => s.exerciseId == squat)
        .map((s) => s.reps)
        .toList();
    expect(reps, [12, 12, 12, 12]);
    final benchReps = d.sets
        .where((s) => s.exerciseId == bench)
        .map((s) => s.reps)
        .toList();
    expect(benchReps, [10, 10, 10]);
  });

  test('② 有氧模板（item durationSec=300）→ 每组 durationSec=300（不是动作库默认）',
      () async {
    final run = await seedExercise('跑步', 'cardio');
    await seedTemplate(
      name: '有氧 5 分钟',
      type: 'cardio',
      minutes: 30,
      items: [
        TemplateItemInput(
            exerciseId: run, targetSets: 2, targetDurationSec: 300),
      ],
    );

    final r = await logWorkout({
      'workout_type': '有氧',
      'minutes': 30,
      'template_name': '有氧 5 分钟',
    });

    final d = await detail(r['workout_id'] as int);
    expect(d.sets, hasLength(2));
    for (final s in d.sets) {
      expect(s.durationSec, 300);
    }
  });

  test('③ 模板不存在 → 抛「没找到模板「X」」', () async {
    expect(
      () => logWorkout({
        'workout_type': '力量',
        'minutes': 30,
        'template_name': '不存在的模板',
      }),
      throwsA(isA<AiToolException>()),
    );
  });

  test('④ 模板无动作 → 抛「还没有动作」', () async {
    await seedTemplate(
        name: '空模板', type: 'strength', minutes: 20, items: const []);

    expect(
      () => logWorkout({
        'workout_type': '力量',
        'minutes': 20,
        'template_name': '空模板',
      }),
      throwsA(isA<AiToolException>()),
    );
  });

  test('⑤ 同时给 template_name 和 exercises → 以模板为准，回执含 template', () async {
    final squat = await seedExercise('深蹲', 'strength');
    await seedExercise('卧推', 'strength');
    await seedTemplate(
      name: '模板优先',
      type: 'strength',
      minutes: 30,
      items: [TemplateItemInput(exerciseId: squat, targetSets: 2, targetReps: 8)],
    );

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 30,
      'template_name': '模板优先',
      'exercises': [
        {'name': '卧推', 'sets': 5, 'reps': 5},
      ],
    });

    expect(r['template'], '模板优先');
    expect(r['set_count'], 2, reason: '以模板（2 组）为准，不是 exercises 的 5 组');
    final d = await detail(r['workout_id'] as int);
    expect(d.sets.every((s) => s.exerciseId == squat), isTrue);
    expect(d.sets.every((s) => s.reps == 8), isTrue);
  });

  test('⑥ 没给 minutes → 用模板 minutes', () async {
    final squat = await seedExercise('深蹲', 'strength');
    await seedTemplate(
      name: '四十分钟',
      type: 'strength',
      minutes: 40,
      items: [TemplateItemInput(exerciseId: squat, targetSets: 1, targetReps: 10)],
    );

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 40,
      'template_name': '四十分钟',
    });
    expect(r['minutes'], 40);
    final d = await detail(r['workout_id'] as int);
    expect(d.durationSec, 40 * 60);
  });

  test('⑦ 无模板路径回归：reps 直传 / 回落默认 / 有氧 minutes', () async {
    final squat = await seedExercise('深蹲', 'strength');
    final push = await seedExercise('俯卧撑', 'strength', defaultReps: 15);
    final run = await seedExercise('跑步', 'cardio');

    final r = await logWorkout({
      'workout_type': '力量',
      'minutes': 30,
      'exercises': [
        {'name': '深蹲', 'sets': 2, 'reps': 12},
        {'name': '俯卧撑', 'sets': 1},
        {'name': '跑步', 'sets': 1, 'minutes': 30},
      ],
    });

    final d = await detail(r['workout_id'] as int);
    final byEx = <int, List<int?>>{};
    for (final s in d.sets) {
      byEx.putIfAbsent(s.exerciseId, () => []).add(s.reps);
    }
    expect(byEx[squat], [12, 12]);
    expect(byEx[push], [15], reason: '回落到动作库默认次数');
    final runSet = d.sets.firstWhere((s) => s.exerciseId == run);
    expect(runSet.durationSec, 1800);
  });

  test('⑧ expandTemplateSets 纯函数：展开/取值/空模板', () {
    const tpl = WorkoutTemplateEntity(
      id: 1,
      name: 'T',
      difficulty: '入门',
      focus: '全身',
      type: 'strength',
      minutes: 30,
      items: [
        WorkoutTemplateItemEntity(
            id: 1,
            templateId: 1,
            exerciseId: 10,
            exerciseName: '深蹲',
            category: 'strength',
            targetSets: 3,
            targetReps: 12),
        WorkoutTemplateItemEntity(
            id: 2,
            templateId: 1,
            exerciseId: 11,
            exerciseName: '拉伸',
            category: 'stretch',
            targetSets: 2,
            targetDurationSec: 45),
      ],
    );

    final sets = expandTemplateSets(tpl);
    expect(sets, hasLength(5), reason: '3 + 2 组');
    expect(sets.where((s) => s.exerciseId == 10).map((s) => s.setNumber),
        [1, 2, 3]);
    expect(sets.where((s) => s.exerciseId == 10).every((s) => s.reps == 12),
        isTrue);
    expect(
        sets
            .where((s) => s.exerciseId == 11)
            .every((s) => s.durationSec == 45),
        isTrue,
        reason: '时长取自 item，不是动作库默认');

    expect(
      () => expandTemplateSets(const WorkoutTemplateEntity(
        id: 2,
        name: '空',
        difficulty: '入门',
        focus: '全身',
        minutes: 10,
      )),
      throwsA(isA<TemplateEmptyException>()),
    );
  });
}
