import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'fake_database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/data/ai_tool_workout_launcher.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/ai_workout_intent.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart'
    show ExerciseSlot;

/// 「开始训练」工具（start_workout）的纯逻辑回归
///
/// 覆盖五类不变量：
/// 1. 工具集合：20 个、唯一、写/只读互斥并集全覆盖，危险仍只 delete_records
/// 2. 模板匹配：trim + 忽略大小写；不存在时**预览阶段**就报错，不弹确认卡
/// 3. 执行语义：不写库，只返回槽位 JSON；rest_sec 的缺省链固定
/// 4. 解析层：工具结果 → ExerciseSlot 列表，任何残缺都返回 null（宁可不跳转）
/// 5. 状态位与提示词：待启动训练能被写入 / 消费，模型被要求直接开练
void main() {
  // ═══════════ 1. 工具集合 ═══════════

  group('start_workout 在工具集合里的位置', () {
    test('21 个工具、唯一、写 16 + 只读 5 正好划分', () {
      final names = AiToolSpecs.defs
          .map((d) => (d['function'] as Map)['name'] as String)
          .toList();

      expect(names, hasLength(21), reason: '20 → 21，总数要同步');
      expect(names.toSet(), hasLength(21), reason: '工具名不能重复');
      expect({...AiToolSpecs.writeTools, ...AiToolSpecs.readOnlyTools},
          names.toSet(),
          reason: '写 / 只读两集合必须正好划分已注册的工具');
      expect(AiToolSpecs.writeTools, hasLength(16));
      expect(AiToolSpecs.readOnlyTools, hasLength(5));
      expect(AiToolSpecs.writeTools.intersection(AiToolSpecs.readOnlyTools),
          isEmpty);
    });

    test('start_workout 是写工具但非危险；危险是 delete_records + wipe_all_data', () {
      expect(AiToolSpecs.writeTools, contains(AiToolSpecs.startWorkout));
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.startWorkout), isFalse,
          reason: '要跳界面，不能自动执行');
      expect(AiToolSpecs.isDestructive(AiToolSpecs.startWorkout), isFalse,
          reason: '不删数据，不能挂危险样式');
      expect(AiToolSpecs.destructiveTools,
          {AiToolSpecs.deleteRecords, AiToolSpecs.wipeAllData});
    });

    test('schema 只要求 template_name，rest_sec 可选', () {
      final def = AiToolSpecs.defs.firstWhere(
          (d) => (d['function'] as Map)['name'] == AiToolSpecs.startWorkout);
      final params = (def['function'] as Map)['parameters'] as Map;
      expect(params['required'], ['template_name']);
      final props = params['properties'] as Map;
      expect(props.keys.toSet(), {'template_name', 'rest_sec'});
    });
  });

  // ═══════════ 2. 模板匹配与确认卡 ═══════════

  group('模板匹配与确认卡', () {
    test('忽略大小写与首尾空格', () async {
      final executor = _executor(templates: const [_mixedCaseTemplate]);
      for (final name in ['abcd 力量', ' ABCD 力量 ', 'AbCd 力量']) {
        final preview = await executor.preview(_call(name));
        expect(preview.detail, startsWith('AbCd 力量'),
            reason: '匹配成功时文案用库里的名字');
      }
    });

    test('模板不存在：预览阶段抛异常，且文案引导新建', () async {
      final executor = _executor();
      await _expectRejected(
        () => executor.preview(_call('上肢力量')),
        mentions: '没找到模板"上肢力量"，要不要我帮你建一个？',
      );
    });

    test('确认卡：label=开始训练、needsConfirm=true、非危险', () async {
      final executor = _executor();
      final preview = await executor.preview(_call('下肢力量'));

      expect(preview.label, '开始训练');
      expect(preview.detail, '下肢力量 · 3 个动作 · 约 30 分钟');
      expect(preview.needsConfirm, isTrue, reason: '要跳界面，必须先让用户点头');
      expect(preview.isDestructive, isFalse);
    });

    test('模板没有动作：预览就拦下，别让用户点了确认才发现练不了', () async {
      final executor = _executor(templates: const [_emptyTemplate]);
      await _expectRejected(() => executor.preview(_call('空模板')),
          mentions: '还没有动作');
    });

    test('缺少模板名 / 名字太长：直接报错', () async {
      final executor = _executor();
      await _expectRejected(
        () => executor.preview(const AiToolCall(
          id: 'c1',
          name: AiToolSpecs.startWorkout,
          argumentsJson: '{}',
        )),
        mentions: '缺少模板名称',
      );
      await _expectRejected(() => executor.preview(_call('x' * 31)),
          mentions: '模板名称太长');
    });
  });

  // ═══════════ 3. 执行：不写库 + rest_sec 缺省链 ═══════════

  group('执行：只返回槽位，不写数据库', () {
    test('返回 ok/action/template/slots 且字段齐全', () async {
      final templates = _MemoryTemplateRepo([_legTemplate]);
      final executor = _executor(templatesRepo: templates);

      final result = await _executeJson(executor, _call('下肢力量'));

      expect(result['ok'], isTrue);
      expect(result['action'], 'start_workout');
      expect(result['template'], '下肢力量');
      final slots = result['slots'] as List<dynamic>;
      expect(slots, hasLength(3));
      final first = slots.first as Map<String, dynamic>;
      expect(first['exerciseId'], 1);
      expect(first['exerciseName'], '深蹲');
      expect(first['category'], 'gym');
      expect(first['targetSets'], 4);
      expect(first['targetReps'], 12);
      expect(first['targetDurationSec'], isNull);
      expect(first['restSec'], 90);
      expect(templates.createCalls, isEmpty, reason: '开始训练绝不能写库');
      expect(templates.updateCalls, isEmpty);
      expect(templates.deleteCalls, isEmpty);
    });

    test('给了 rest_sec 就用它（10~300 之外拒绝）', () async {
      final executor = _executor();
      final result = await _executeJson(executor, _call('下肢力量', restSec: 30));
      for (final slot in result['slots'] as List<dynamic>) {
        expect((slot as Map)['restSec'], 30);
      }

      for (final bad in [9, 301]) {
        await _expectRejected(
            () => executor.preview(_call('下肢力量', restSec: bad)),
            mentions: '休息时长不合理');
      }
    });

    test('没给 rest_sec：用设置里的 restShortSec', () async {
      final executor = _executor(
          settings:
              const _FakeSettingsRepo(restShortSec: 45, defaultRestSec: 120));
      final result = await _executeJson(executor, _call('下肢力量'));
      expect((result['slots'] as List<dynamic>).first,
          containsPair('restSec', 45));
    });

    test('设置里没有 restShortSec：退到 defaultRestSec', () async {
      final executor =
          _executor(settings: const _FakeSettingsRepo(defaultRestSec: 120));
      final result = await _executeJson(executor, _call('下肢力量'));
      expect((result['slots'] as List<dynamic>).first,
          containsPair('restSec', 120));
    });

    test('设置全空 / 取值非法 / 读不出来：兜底 90', () async {
      const fallback = AiToolWorkoutLauncher.fallbackRestSec;
      for (final executor in [
        _executor(settings: const _FakeSettingsRepo()),
        // 0 与负数都不是合法休息时长，必须被跳过
        _executor(
            settings: const _FakeSettingsRepo(
                restShortSec: 0, defaultRestSec: -5)),
        _executor(settings: const _BrokenSettingsRepo()),
      ]) {
        final result = await _executeJson(executor, _call('下肢力量'));
        expect((result['slots'] as List<dynamic>).first,
            containsPair('restSec', fallback));
      }
    });
  });

  // ═══════════ 4. 解析层：工具结果 → 槽位 ═══════════

  group('parseWorkoutSlots', () {
    test('正常 JSON：数量与字段都对', () {
      final slots = parseWorkoutSlots(jsonEncode({
        'ok': true,
        'action': 'start_workout',
        'template': '下肢力量',
        'slots': [
          {
            'exerciseId': 1,
            'exerciseName': '深蹲',
            'category': 'gym',
            'targetSets': 3,
            'targetReps': 12,
            'targetDurationSec': null,
            'restSec': 90,
          },
          {
            'exerciseId': 2,
            'exerciseName': '平板支撑',
            'category': 'bodyweight',
            'targetSets': 3,
            'targetReps': null,
            'targetDurationSec': 45,
            'restSec': 60,
          },
        ],
      }));

      expect(slots, isNotNull);
      expect(slots, hasLength(2));
      final first = slots!.first;
      expect(first.exerciseId, 1);
      expect(first.exerciseName, '深蹲');
      expect(first.category, 'gym');
      expect(first.targetSets, 3);
      expect(first.targetReps, 12);
      expect(first.targetDurationSec, isNull);
      expect(first.restSec, 90);
      final second = slots.last;
      expect(second.targetReps, isNull);
      expect(second.targetDurationSec, 45);
      expect(second.restSec, 60);
    });

    test('模板名一起解析出来（空白时用兜底名）', () {
      expect(
          AiWorkoutIntent.parse(_okJson(template: '下肢力量'))!.templateName,
          '下肢力量');
      expect(
          AiWorkoutIntent.parse(_okJson(template: '   '))!.templateName,
          AiWorkoutIntent.fallbackTemplateName);
    });

    test('slots 为空 / ok 不为 true / 非法 JSON → null', () {
      expect(parseWorkoutSlots('{"ok":true,"slots":[]}'), isNull);
      expect(
          parseWorkoutSlots('{"ok":false,"slots":[{"exerciseId":1}]}'), isNull);
      expect(parseWorkoutSlots('not json'), isNull);
      expect(parseWorkoutSlots(''), isNull);
      expect(parseWorkoutSlots('{"ok":true,"slots":"深蹲"}'), isNull);
    });

    test('必填字段缺失或类型错 → 整条 null（宁可重试也不跳半残页面）', () {
      // 缺 exerciseId
      expect(
          parseWorkoutSlots('{"ok":true,"slots":[{"exerciseName":"深蹲",'
              '"category":"gym","targetSets":3}]}'),
          isNull);
      // exerciseId 类型错
      expect(
          parseWorkoutSlots('{"ok":true,"slots":[{"exerciseId":"abc",'
              '"exerciseName":"深蹲","category":"gym","targetSets":3}]}'),
          isNull);
      // 组数为 0
      expect(
          parseWorkoutSlots('{"ok":true,"slots":[{"exerciseId":1,'
              '"exerciseName":"深蹲","category":"gym","targetSets":0}]}'),
          isNull);
      // 可选字段给了但不是数字
      expect(
          parseWorkoutSlots('{"ok":true,"slots":[{"exerciseId":1,'
              '"exerciseName":"深蹲","category":"gym","targetSets":3,'
              '"targetReps":"多"}]}'),
          isNull);
      // 第一条好、第二条坏 → 整体失败，不能只带一半动作进训练页
      expect(
          parseWorkoutSlots('{"ok":true,"slots":[{"exerciseId":1,'
              '"exerciseName":"深蹲","category":"gym","targetSets":3},'
              '{"exerciseId":2}]}'),
          isNull);
    });

    test('槽位缺 restSec 时用兜底 90', () {
      final slots = parseWorkoutSlots('{"ok":true,"slots":[{"exerciseId":1,'
          '"exerciseName":"深蹲","category":"gym","targetSets":3}]}');
      expect(slots!.single.restSec, AiWorkoutIntent.fallbackRestSec);
    });
  });

  // ═══════════ 5. 状态位与提示词 ═══════════

  group('待启动训练的状态位', () {
    test('默认没有待启动训练；copyWith 能写入也能清空', () {
      const state = AiChatState();
      expect(state.pendingWorkoutStart, isNull);
      expect(state.pendingWorkoutTemplateName, isNull);
      expect(state.hasPendingWorkoutStart, isFalse);

      final pending = state.copyWith(
        pendingWorkoutStart: const [
          ExerciseSlot(
            exerciseId: 1,
            exerciseName: '深蹲',
            category: 'gym',
            targetSets: 3,
          ),
        ],
        pendingWorkoutTemplateName: '下肢力量',
      );
      expect(pending.hasPendingWorkoutStart, isTrue);
      expect(pending.pendingWorkoutTemplateName, '下肢力量');

      final consumed = pending.copyWith(clearPendingWorkout: true);
      expect(consumed.pendingWorkoutStart, isNull);
      expect(consumed.pendingWorkoutTemplateName, isNull);
      expect(consumed.hasPendingWorkoutStart, isFalse);
    });

    test('待启动训练不算 isBusy（否则返回聊天页后输入框会被禁用）', () {
      final state = const AiChatState().copyWith(pendingWorkoutStart: const [
        ExerciseSlot(
          exerciseId: 1,
          exerciseName: '深蹲',
          category: 'gym',
          targetSets: 3,
        ),
      ]);
      expect(state.isBusy, isFalse);
    });
  });

  group('提示词：开始训练的两条规则', () {
    test('引导调用 start_workout，不要只描述模板', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('start_workout'));
      expect(prompt, contains('帮我打开模板'));
      expect(prompt, contains('不要只描述模板内容'));
    });

    test('不知道有哪些模板时先看 query_stats 的 templates，别编名字', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('templates'));
      expect(prompt, contains('没找到模板'));
    });

    test('能力询问（有没有按钮）也要直接开练，不许回答做不到', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('有没有按钮'));
      expect(prompt, contains('不要回答"我没有按钮 / 我做不到"'));
      expect(prompt, contains('做给他看'));
    });
  });
}

// ═══════════════════════ 测试辅助 ═══════════════════════

/// 下肢力量：深蹲 4×12 / 臀桥 3×15 / 平板支撑 3×45s，约 30 分钟
const _legTemplate = WorkoutTemplateEntity(
  id: 7,
  name: '下肢力量',
  difficulty: '中阶',
  focus: '全身',
  minutes: 30,
  items: [
    WorkoutTemplateItemEntity(
      id: 1,
      templateId: 7,
      exerciseId: 1,
      exerciseName: '深蹲',
      category: 'gym',
      targetSets: 4,
      targetReps: 12,
    ),
    WorkoutTemplateItemEntity(
      id: 2,
      templateId: 7,
      exerciseId: 2,
      exerciseName: '臀桥',
      category: 'bodyweight',
      targetSets: 3,
      targetReps: 15,
    ),
    WorkoutTemplateItemEntity(
      id: 3,
      templateId: 7,
      exerciseId: 3,
      exerciseName: '平板支撑',
      category: 'bodyweight',
      targetSets: 3,
      targetDurationSec: 45,
    ),
  ],
);

/// 名字大小写混杂的同一个模板（测"忽略大小写"匹配）
const _mixedCaseTemplate = WorkoutTemplateEntity(
  id: 8,
  name: 'AbCd 力量',
  difficulty: '中阶',
  focus: '全身',
  minutes: 30,
  items: [
    WorkoutTemplateItemEntity(
      id: 4,
      templateId: 8,
      exerciseId: 1,
      exerciseName: '深蹲',
      category: 'gym',
      targetSets: 4,
      targetReps: 12,
    ),
  ],
);

/// 没有动作的模板：开练没有意义，必须拦下
const _emptyTemplate = WorkoutTemplateEntity(
  id: 9,
  name: '空模板',
  difficulty: '入门',
  focus: '碎片',
  minutes: 10,
);

/// 构造一条 start_workout 调用
AiToolCall _call(String templateName, {int? restSec}) => AiToolCall(
      id: 'call_sw_$templateName',
      name: AiToolSpecs.startWorkout,
      argumentsJson: jsonEncode({
        'template_name': templateName,
        if (restSec != null) 'rest_sec': restSec,
      }),
    );

/// 一条 ok:true 的工具结果（模板名可指定）
String _okJson({required String template}) => jsonEncode({
      'ok': true,
      'action': 'start_workout',
      'template': template,
      'slots': [
        {
          'exerciseId': 1,
          'exerciseName': '深蹲',
          'category': 'gym',
          'targetSets': 3,
          'targetReps': 12,
          'targetDurationSec': null,
          'restSec': 90,
        },
      ],
    });

Future<Map<String, dynamic>> _executeJson(
    AiToolExecutor executor, AiToolCall call) async {
  final raw = await executor.execute(call);
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<void> _expectRejected(
  Future<Object?> Function() action, {
  required String mentions,
}) async {
  try {
    await action();
  } on AiToolException catch (e) {
    expect(e.message, contains(mentions));
    return;
  }
  fail('应当抛出 AiToolException 并提示「$mentions」，但没有抛');
}

/// 组装执行器（只用模板库与设置，其余仓储不可被碰到）
AiToolExecutor _executor({
  List<WorkoutTemplateEntity> templates = const [_legTemplate],
  _MemoryTemplateRepo? templatesRepo,
  UserSettingsRepository settings = const _FakeSettingsRepo(),
}) =>
    AiToolExecutor(
      repos: AiToolRepos(
        database: fakeDatabase(),
        body: const _UntouchedBodyRepo(),
        water: const _UntouchedWaterRepo(),
        workout: const _UntouchedWorkoutRepo(),
        diet: const _UntouchedDietRepo(),
        goal: const _UntouchedGoalRepo(),
        settings: settings,
        exercise: const _UntouchedExerciseRepo(),
        template: templatesRepo ?? _MemoryTemplateRepo(templates),
      ),
    );

/// 记录写操作的模板库（开始训练不该碰它）
class _MemoryTemplateRepo implements WorkoutTemplateRepository {
  _MemoryTemplateRepo(this.rows);

  final List<WorkoutTemplateEntity> rows;

  final List<String> createCalls = <String>[];
  final List<int> updateCalls = <int>[];
  final List<int> deleteCalls = <int>[];

  @override
  Future<List<WorkoutTemplateEntity>> getAll() async => rows;

  @override
  Future<WorkoutTemplateEntity?> getById(int id) async {
    for (final t in rows) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    createCalls.add(name);
    return 1;
  }

  @override
  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    updateCalls.add(id);
  }

  @override
  Future<void> delete(int id) async {
    deleteCalls.add(id);
  }
}

/// 设置仓储：只关心休息时长的两级默认值
class _FakeSettingsRepo implements UserSettingsRepository {
  const _FakeSettingsRepo({this.restShortSec, this.defaultRestSec});

  final int? restShortSec;
  final int? defaultRestSec;

  @override
  Future<UserSettingsEntity?> get() async => UserSettingsEntity(
        id: 1,
        restShortSec: restShortSec,
        defaultRestSec: defaultRestSec,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练只读设置，不写入');
}

/// 设置读不出来：缺省链必须继续兜底到 90，而不是把异常抛给用户
class _BrokenSettingsRepo implements UserSettingsRepository {
  const _BrokenSettingsRepo();

  @override
  Future<UserSettingsEntity?> get() async => throw StateError('设置表读不出来');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练只读设置，不写入');
}

// ═══════════ 不该被碰到的仓储（开始训练只查模板 + 读设置） ═══════════

class _UntouchedBodyRepo implements BodyMetricRepository {
  const _UntouchedBodyRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 body 仓储');
}

class _UntouchedWaterRepo implements WaterRepository {
  const _UntouchedWaterRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 water 仓储');
}

class _UntouchedWorkoutRepo implements WorkoutRepository {
  const _UntouchedWorkoutRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 workout 仓储');
}

class _UntouchedDietRepo implements DietRepository {
  const _UntouchedDietRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 diet 仓储');
}

class _UntouchedGoalRepo implements GoalRepository {
  const _UntouchedGoalRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 goal 仓储');
}

class _UntouchedExerciseRepo implements ExerciseRepository {
  const _UntouchedExerciseRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('开始训练不该访问 exercise 仓储');
}
