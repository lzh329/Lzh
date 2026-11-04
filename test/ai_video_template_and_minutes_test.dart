import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

import 'fake_database.dart';

/// 两个需求的门禁：
/// ① 视频链接 → 一键建模板（提示词里的动作链，不新增工具）
/// ② update_workout 支持可选 minutes（不传就不动）
void main() {
  group('① 视频链接 → 建模板：提示词动作链', () {
    const emptyTrends = TrendsData();

    String prompt({bool web = true}) => AiPromptBuilder.build(
          trends: emptyTrends,
          settings: UserSettingsEntity(id: 1, aiWebSearchEnabled: web),
        );

    test('联网开启时：fetch_url 读页 → 提类型/时长 → 直接 create_template', () {
      final p = prompt();
      // 必须是同一条规则里串起"读页 → 提取 → 建模板"
      expect(p, contains('用户发**视频链接**并要「按这个建模板」时'));
      expect(p, contains('先 fetch_url 读标题/简介'));
      expect(p, contains('create_template'));
      expect(p, contains('minutes 用提取值'));
      expect(p, contains('create_missing_exercises: true'));
    });

    test('强调"组次不要编 / 提不到就说不看画面 / 别让用户以为看了视频"', () {
      final p = prompt();
      expect(p, contains('不要编'));
      expect(p, contains('看不到画面'));
      expect(p, contains('绝不虚构视频里没有的动作'));
      expect(p, contains('按标题/简介推断'));
    });

    test('联网关闭时整段不出现（关掉搜索就不能再让他去 fetch_url）', () {
      final p = prompt(web: false);
      expect(p, isNot(contains('用户发**视频链接**并要「按这个建模板」时')));
      expect(p, contains('联网已关闭'));
    });

    test('没有新增工具：create_template 本来就在工具清单里，不额外加 schema', () {
      final p = prompt();
      // 规则里只出现现有工具，不出现新工具名
      expect(p.contains('create_template_from_video'), isFalse);
      expect(p.contains('parse_video'), isFalse);
    });
  });

  group('② update_workout 支持可选 minutes', () {
    late AppDatabase db;
    late AiToolWriters writers;

    setUp(() async {
      db = fakeDatabase();
      writers = AiToolWriters(fakeToolRepos(db));
      await db.into(db.exercises).insert(
          ExercisesCompanion.insert(name: '深蹲', category: 'gym'));
    });

    tearDown(() async => db.close());

    Future<Map<String, dynamic>> call(
        String name, Map<String, dynamic> args) async {
      final res = await writers.execute(AiToolCall(
        id: 'call-1',
        name: name,
        argumentsJson: jsonEncode(args),
      ));
      return jsonDecode(res) as Map<String, dynamic>;
    }

    /// 造一条 45 分钟、3 组深蹲的记录
    Future<int> seedWorkout() async {
      await call(AiToolSpecs.logWorkout, {
        'workout_type': '力量',
        'minutes': 45,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12},
        ],
      });
      return (await db.select(db.workouts).getSingle()).id;
    }

    test('schema 里确实有可选 minutes（1~600，说明"没说要改就别传"）', () {
      final updateDef = AiToolSpecs.defs.firstWhere(
          (d) => (d['function'] as Map)['name'] == AiToolSpecs.updateWorkout);
      final props =
          ((updateDef['function'] as Map)['parameters'] as Map)['properties']
              as Map;
      expect(props.containsKey('minutes'), isTrue, reason: '缺 minutes 用户就只能改动作');
      final minutes = props['minutes'] as Map;
      expect(minutes['type'], 'integer');
      expect(minutes['description'], contains('1~600'));
      expect(minutes['description'], contains('不要传'));
    });

    test('不带 minutes → 时长不变、动作被替换（回归，别把时长顺手清空）', () async {
      final id = await seedWorkout();
      expect((await db.select(db.workouts).getSingle()).durationSec, 45 * 60);

      final res = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'exercises': [
          {'name': '深蹲', 'sets': 5, 'reps': 8},
        ],
      });

      expect(res['ok'], true);
      final row = await db.select(db.workouts).getSingle();
      expect(row.durationSec, 45 * 60, reason: '没传 minutes 就不许动时长');
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(5), reason: '动作照旧整体替换');
    });

    test('带 minutes=30 → 时长改成 30 分钟，动作也被替换', () async {
      final id = await seedWorkout();

      final res = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'minutes': 30,
        'exercises': [
          {'name': '深蹲', 'sets': 2, 'reps': 10},
        ],
      });

      expect(res['ok'], true);
      expect(res['duration_minutes'], 30);
      final row = await db.select(db.workouts).getSingle();
      expect(row.durationSec, 30 * 60);
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(2));
      expect(sets.every((s) => s.reps == 10), isTrue);
    });

    test('回执里的 duration_minutes：没改就给原值，改了给新值', () async {
      final id = await seedWorkout();

      final unchanged = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12},
        ],
      });
      expect(unchanged['duration_minutes'], 45, reason: '模型要据此复述"还是 45 分钟"');

      final changed = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'minutes': 90,
        'exercises': [
          {'name': '深蹲', 'sets': 3, 'reps': 12},
        ],
      });
      expect(changed['duration_minutes'], 90);
    });

    test('非法 minutes（0 / 601 / 非数字）→ 抛 AiToolException，库里一个字节不动', () async {
      final id = await seedWorkout();

      for (final bad in [0, 601, 'abc']) {
        await expectLater(
          call(AiToolSpecs.updateWorkout, {
            'workout_id': id,
            'minutes': bad,
            'exercises': [
              {'name': '深蹲', 'sets': 9, 'reps': 9},
            ],
          }),
          throwsA(isA<AiToolException>()),
          reason: 'minutes=$bad 必须被拦下',
        );
      }

      final row = await db.select(db.workouts).getSingle();
      expect(row.durationSec, 45 * 60, reason: '校验失败不许写库');
      expect(await db.select(db.workoutSets).get(), hasLength(3),
          reason: '校验失败也不许替换动作');
    });

    // ⚠️ 主理人复核发现的漏洞：只传 minutes（不传 exercises）曾经把动作全删光
    // （`_resolveSets([])` → `[]` → 仓库无条件先删再插 0 条）。
    test('**只传 minutes（不传 exercises）→ 时长改成 45 分钟，原有 3 组一条不少**',
        () async {
      final id = await seedWorkout(); // 3 组深蹲 · 45 分钟
      expect(await db.select(db.workoutSets).get(), hasLength(3));

      final res = await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'minutes': 20,
      });

      expect(res['ok'], true);
      final row = await db.select(db.workouts).getSingle();
      expect(row.durationSec, 20 * 60, reason: '时长要改');
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(3), reason: '**动作必须一条不少**（这是本次漏洞的回归锁）');
      expect(sets.every((s) => s.reps == 12), isTrue);
      expect(res['exercise_count'], 1, reason: '回执要报"没动过"的动作数');
    });

    test('**只传 exercises（不传 minutes）→ 动作整体替换、时长不动**', () async {
      final id = await seedWorkout();

      await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'exercises': [
          {'name': '深蹲', 'sets': 5, 'reps': 8},
        ],
      });

      expect((await db.select(db.workouts).getSingle()).durationSec, 45 * 60);
      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(5), reason: '原 3 组 → 新 5 组（防修过头）');
      expect(sets.every((s) => s.reps == 8), isTrue);
    });

    test('两个都不传（只改备注）→ 动作与时长都保持', () async {
      final id = await seedWorkout();

      await call(AiToolSpecs.updateWorkout, {
        'workout_id': id,
        'note': '今天状态不错',
      });

      final row = await db.select(db.workouts).getSingle();
      expect(row.note, '今天状态不错');
      expect(row.durationSec, 45 * 60, reason: '没传 minutes 就不动时长');
      expect(await db.select(db.workoutSets).get(), hasLength(3),
          reason: '没传 exercises 就不动动作');
    });

    test('确认卡文案：带 minutes 时体现「时长 X 分钟」，不带时不出现', () async {
      final id = await seedWorkout();

      final withMinutes = await writers.preview(AiToolCall(
        id: 'p1',
        name: AiToolSpecs.updateWorkout,
        argumentsJson: jsonEncode({
          'workout_id': id,
          'minutes': 25,
          'exercises': [
            {'name': '深蹲'},
          ],
        }),
      ));
      expect(withMinutes.detail, contains('#$id'));
      expect(withMinutes.detail, contains('时长 25 分钟'));

      final withoutMinutes = await writers.preview(AiToolCall(
        id: 'p2',
        name: AiToolSpecs.updateWorkout,
        argumentsJson: jsonEncode({
          'workout_id': id,
          'exercises': [
            {'name': '深蹲'},
          ],
        }),
      ));
      expect(withoutMinutes.detail.contains('时长'), isFalse,
          reason: '没改时长就别在确认卡上写时长，免得用户以为要改');
    });
  });
}
