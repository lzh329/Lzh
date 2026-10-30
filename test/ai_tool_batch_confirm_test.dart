import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'fake_database.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// 「批量一次确认」改造的安全回归（纯逻辑，不连数据库）
///
/// 覆盖四类不变量：
/// 1. 确认闸门没有被批量放宽（三个动作 / 模板工具都需确认、都不算危险操作）
/// 2. `create_missing_exercises` 为 false 时绝不新建动作（只报错、不写库）
/// 3. 同名动作不会被建第二次（库内大小写 / 空格差异、批内重名、批内与库内混合）
/// 4. 分类兜底必须是 bodyweight（写 other 会让动作在分类筛选里消失）
///
/// 外加 preview 与 execute 之间「库被改动」时的一致性与安全性。
void main() {
  // ═══════════ 1. 确认闸门：批量不许免确认 ═══════════

  group('确认闸门没有被批量放宽', () {
    test('三个动作 / 模板工具：都要确认、都不是危险操作', () async {
      final executor = AiToolExecutor(repos: _repos());

      final cases = <String, AiToolCall>{
        AiToolSpecs.createExercise: const AiToolCall(
          id: 'call_ce',
          name: AiToolSpecs.createExercise,
          argumentsJson: '{"name":"保加利亚分腿蹲","category":"器械"}',
        ),
        AiToolSpecs.createExercises: _exercisesCall(const [
          {'name': '开合跳', 'category': '有氧'},
          {'name': '深蹲跳', 'category': '徒手'},
        ]),
        AiToolSpecs.createTemplate: _templateCall(const [
          {'exercise_name': '深蹲', 'sets': 4, 'reps': 12},
        ]),
      };

      for (final entry in cases.entries) {
        final preview = await executor.preview(entry.value);
        expect(preview.needsConfirm, isTrue,
            reason: '${entry.key} 是写操作，必须弹确认卡（批量也不许免确认）');
        expect(preview.isDestructive, isFalse,
            reason: '${entry.key} 不删数据，不能挂危险样式');
        expect(preview.detail, isNotEmpty,
            reason: '${entry.key} 的确认文案不能为空');
      }
    });

    test('25 个工具：写 19 + 只读 6 正好覆盖，危险 = 三个删除类', () {
      final registered = AiToolSpecs.defs
          .map((d) => (d['function'] as Map)['name'] as String)
          .toSet();

      expect(registered, hasLength(25), reason: '工具总数没同步');
      expect(AiToolSpecs.writeTools, hasLength(19), reason: '写工具应为 18 个');
      expect(AiToolSpecs.readOnlyTools, hasLength(6), reason: '只读工具应为 6 个');
      expect({...AiToolSpecs.writeTools, ...AiToolSpecs.readOnlyTools}, registered,
          reason: '写 / 只读两集合必须正好划分已注册的工具');
      expect(AiToolSpecs.writeTools.intersection(AiToolSpecs.readOnlyTools), isEmpty,
          reason: '同一个工具不能既是写又是只读（否则可以绕过确认）');
      expect(
          AiToolSpecs.destructiveTools,
          {
            AiToolSpecs.deleteRecords,
            AiToolSpecs.deleteMeasurement,
            AiToolSpecs.deleteTemplate,
            AiToolSpecs.wipeAllData,
          },
          reason: '危险工具：删记录 / 删身体记录 / 清空全部数据');
      expect(AiToolSpecs.destructiveTools.difference(AiToolSpecs.writeTools), isEmpty,
          reason: '危险工具必须同时是写操作');
      expect(AiToolSpecs.writeTools, contains(AiToolSpecs.createExercises));
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.createExercises), isFalse);
    });

    test('notifier 只有两条执行路径：确认后执行、只读直接执行（无第三条旁路）', () {
      final source = File(
        'lib/features/ai/presentation/notifiers/ai_chat_notifier.dart',
      ).readAsStringSync();

      // 轮次上限必须引用常量，不能回退成硬编码的 2
      expect(source, contains('AiToolLimits.maxCallsPerRound'),
          reason: '上限改成 8 后必须用共享常量，避免判定与文案两处漂移');
      expect(source, contains('AiToolLimits.overLimitMessage'));
      expect(RegExp(r'round\s*>=\s*2\b').hasMatch(source), isFalse,
          reason: '不能残留上限放开之前的硬编码 2');

      // 写操作必须先挂 pendingTool 等用户点头
      expect(source, contains('if (preview.needsConfirm)'));
      expect(source, contains('pendingTool: preview'));
      // execute 只允许出现在 confirmTool（用户确认）与只读分支各一次
      final executeCalls =
          RegExp(r'_executor\.execute\(').allMatches(source).length;
      expect(executeCalls, 2,
          reason: 'execute 只应有两处调用：确认后的 confirmTool 与 needsConfirm=false 的只读分支');
    });
  });

  // ═══════════ 2. 开关为 false：绝不新建动作 ═══════════

  group('create_missing_exercises = false 时绝不新建动作', () {
    const missingItem = [
      {'exercise_name': '开合跳', 'category': '有氧'},
    ];

    test('省略开关：preview 抛「动作库里没有」，且一个字都没写库', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));

      await _expectRejected(
        () => executor.preview(_templateCall(missingItem)),
        mentions: '动作库里没有"开合跳"',
      );

      expect(exercise.createCalls, isEmpty, reason: '预览阶段绝不能新建动作');
      expect(exercise.rows, hasLength(_seed.length));
      expect(template.created, isEmpty);
    });

    test('显式 false：preview 与 execute 都报错，库前后完全一致', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));
      final call = _templateCall(missingItem, createMissing: false);
      final before = exercise.names;

      await _expectRejected(() => executor.preview(call),
          mentions: '动作库里没有"开合跳"');
      // 即使跳过预览直接执行（等价于用户直接点了确认），也必须拦住
      await _expectRejected(() => executor.execute(call),
          mentions: '动作库里没有"开合跳"');

      expect(exercise.createCalls, isEmpty, reason: '开关为 false 时不允许任何动作写入');
      expect(exercise.names, before, reason: '动作库不能被这条调用改动');
      expect(template.created, isEmpty, reason: '动作缺失时模板也不能落库');
    });

    test('开关是字符串 "false" 也按 false 处理（宁可不写库）', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final executor = AiToolExecutor(repos: _repos(exercise: exercise));
      final call = _templateCall(missingItem, createMissing: 'false');

      await _expectRejected(() => executor.execute(call), mentions: '动作库里没有');
      expect(exercise.createCalls, isEmpty);
    });

    test('开关值无法识别（如 "maybe"）按 false 兜底，绝不当成 true', () {
      final command = AiToolArgs.template({
        'name': '下肢力量',
        'difficulty': '中阶',
        'focus': '全身',
        'minutes': 30,
        'create_missing_exercises': 'maybe',
        'items': [
          {'exercise_name': '开合跳'},
        ],
      });
      expect(command.createMissingExercises, isFalse,
          reason: '解析不了就当没开，宁可让用户先加动作');
    });
  });

  // ═══════════ 3. 同名动作不会被建第二次 ═══════════

  group('同名动作不会被建第二次', () {
    test('库内已有" Plank "：空格 / 大小写不同也算同名，直接复用不新建', () async {
      final exercise = _MemoryExerciseRepo(const [
        ExerciseEntity(id: 9, name: ' Plank ', category: 'bodyweight'),
      ]);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));
      final call = _templateCall(const [
        {'exercise_name': 'plank', 'sets': 3, 'duration_sec': 45},
      ], createMissing: true);

      final preview = await executor.preview(call);
      expect(preview.detail, isNot(contains('含新建')),
          reason: '库里已有同名动作，不该谎报要新建');

      final result = await _executeJson(executor, call);
      expect(result['created_exercises'], isEmpty, reason: '已存在就该复用');
      expect(exercise.createCalls, isEmpty,
          reason: '不允许因为空格 / 大小写差异再建一条');
      expect(exercise.rows, hasLength(1));
      expect(template.created.single.items.single.exerciseId, 9,
          reason: '模板项必须指向库里已有的那条');
    });

    test('create_exercises：库内 + 批内重名混在一起，只建真正新的', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final executor = AiToolExecutor(repos: _repos(exercise: exercise));

      final result = await _executeJson(
        executor,
        _exercisesCall(const [
          {'name': '深蹲', 'category': '器械'},
          {'name': ' 深蹲 ', 'category': '器械'},
          {'name': '开合跳', 'category': '有氧'},
          {'name': '开合跳 ', 'category': '徒手'},
          {'name': 'Plank', 'category': '徒手'},
        ]),
      );

      expect(result['created_count'], 2, reason: '只有开合跳 / Plank 是新的');
      expect(result['skipped'], ['深蹲']);
      expect(exercise.rows, hasLength(_seed.length + 2));
      final keys =
          exercise.rows.map((e) => e.name.trim().toLowerCase()).toList();
      expect(keys.toSet(), hasLength(keys.length),
          reason: '动作库里不允许出现同名重复项');
    });

    test('create_template 里同名缺失动作只建一个，两个 item 指向同一 id', () async {
      final exercise = _MemoryExerciseRepo(const []);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));

      final result = await _executeJson(
        executor,
        _templateCall(const [
          {'exercise_name': '开合跳', 'category': '有氧'},
          {'exercise_name': ' 开合跳', 'category': '徒手'},
        ], createMissing: true),
      );

      expect(result['created_exercises'], ['开合跳'], reason: '同名只建一次');
      expect(exercise.rows, hasLength(1));
      final ids =
          template.created.single.items.map((e) => e.exerciseId).toList();
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1), reason: '两个 item 必须指向同一个新建动作');
    });
  });

  // ═══════════ 4. 分类兜底 ═══════════

  group('新建动作的分类兜底', () {
    test('没给 category 时落库为 bodyweight，绝不是 other', () async {
      final exercise = _MemoryExerciseRepo(const []);
      final executor = AiToolExecutor(repos: _repos(exercise: exercise));

      await _executeJson(
        executor,
        _templateCall(const [
          {'exercise_name': '开合跳'},
        ], createMissing: true),
      );

      final created = exercise.rows.single;
      expect(created.category, 'bodyweight',
          reason: '动作库 UI 只认 bodyweight/gym/cardio/stretch，兜底写 other '
              '会让该动作在分类筛选里消失');
      expect(created.category, isNot('other'),
          reason: 'other 不是合法分类，分类筛选栏遍历 AiExerciseCategories.all 取不到它');
      expect(AiExerciseCategories.all, contains(created.category),
          reason: '兜底值必须落在 UI 支持的三类里');
      expect(AiExerciseCategories.fallback, AiExerciseCategories.strength);
    });

    test('给了 category 就用给的（兜底不能盖掉模型的选择）', () async {
      final exercise = _MemoryExerciseRepo(const []);
      final executor = AiToolExecutor(repos: _repos(exercise: exercise));

      await _executeJson(
        executor,
        _templateCall(const [
          {'exercise_name': '开合跳', 'category': '有氧', 'muscle_group': '腿部'},
        ], createMissing: true),
      );

      expect(exercise.rows.single.category, 'cardio');
      expect(exercise.rows.single.muscleGroup, '腿部');
    });
  });

  // ═══════════ 5. create_exercises 边界 ═══════════

  group('create_exercises 数量边界', () {
    List<Map<String, dynamic>> batch(int count) => [
          for (var i = 1; i <= count; i++)
            {'name': '动作$i', 'category': '徒手'},
        ];

    test('1 个 / 10 个接受；0 个 / 11 个拒绝', () {
      expect(AiToolArgs.exercises({'exercises': batch(1)}), hasLength(1));
      expect(AiToolArgs.exercises({'exercises': batch(10)}), hasLength(10));
      expect(() => AiToolArgs.exercises({'exercises': batch(0)}),
          throwsA(isA<AiToolException>()));
      expect(
        () => AiToolArgs.exercises({'exercises': batch(11)}),
        throwsA(isA<AiToolException>().having((e) => e.message, 'message',
            contains('${AiToolArgs.maxBatchExercises}'))),
      );
    });

    test('结构不合法（非数组 / 元素不是对象）直接拒绝', () {
      expect(() => AiToolArgs.exercises({'exercises': '开合跳'}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.exercises(const {'exercises': ['开合跳']}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.exercises(const {'exercises': <Object>[]}),
          throwsA(isA<AiToolException>()));
    });

    test('10 个动作一次全部落库，且没有多余写入', () async {
      final exercise = _MemoryExerciseRepo(const []);
      final executor = AiToolExecutor(repos: _repos(exercise: exercise));

      final result = await _executeJson(executor, _exercisesCall(batch(10)));

      expect(result['created_count'], 10);
      expect(result['skipped'], isEmpty);
      expect(exercise.rows, hasLength(10));
      expect(exercise.createCalls, hasLength(10));
    });
  });

  // ═══════════ 6. 轮次上限常量 ═══════════

  group('工具轮次上限 = 8', () {
    test('常量值与文案同步，且提示引导用户分两步说', () {
      expect(AiToolLimits.maxCallsPerRound, 8);
      expect(AiToolLimits.overLimitMessage, contains('操作次数过多'));
      expect(AiToolLimits.overLimitMessage, contains('分两步说'),
          reason: '提示要告诉用户怎么说，而不是只报错');
    });
  });

  // ═══════════ 7. preview 与 execute 之间库被改动 ═══════════

  group('确认期间动作库变化：执行阶段以最新库为准', () {
    test('预览时动作在库 + 开关 false + 确认前被删 → 执行报错，模板不落库', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));
      final call = _templateCall(const [
        {'exercise_name': '深蹲', 'sets': 4, 'reps': 12},
      ], createMissing: false);

      final preview = await executor.preview(call);
      expect(preview.detail, isNot(contains('含新建')),
          reason: '预览时动作都在库里');

      // 用户还在看确认卡的时候，别处把这个动作删了
      exercise.rows.removeWhere((e) => e.name == '深蹲');

      await _expectRejected(() => executor.execute(call),
          mentions: '动作库里没有"深蹲"');
      expect(template.created, isEmpty,
          reason: '动作解析不出 id 时，模板不能半成品落库');
      expect(exercise.createCalls, isEmpty,
          reason: '宁可报错也不替用户静默新建一个他没被知会的动作');
    });

    test('预览时动作在库 + 开关 true + 确认前被删 → 执行补建（宁可多建也不报错）', () async {
      final exercise = _MemoryExerciseRepo(_seed);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));
      final call = _templateCall(const [
        {'exercise_name': '深蹲', 'category': '器械'},
      ], createMissing: true);

      final preview = await executor.preview(call);
      expect(preview.detail, isNot(contains('含新建')),
          reason: '预览那一刻 0 个待建动作 —— 文案会少报');

      exercise.rows.removeWhere((e) => e.name == '深蹲');

      final result = await _executeJson(executor, call);
      expect(result['created_exercises'], ['深蹲'],
          reason: '开关为 true 时补建，避免用户点了确认却建不出模板');
      final newId = exercise.rows.last.id;
      expect(template.created.single.items.single.exerciseId, newId,
          reason: '模板必须指向真正落库的那条动作');
    });

    test('预览说「含新建 2 个」+ 确认期间外部建好 1 个 → 只建 1 个，不重复', () async {
      final exercise = _MemoryExerciseRepo(const []);
      final template = _MemoryTemplateRepo();
      final executor =
          AiToolExecutor(repos: _repos(exercise: exercise, template: template));
      final call = _templateCall(const [
        {'exercise_name': '开合跳', 'category': '有氧'},
        {'exercise_name': '提膝下压', 'category': '徒手'},
      ], createMissing: true);

      final preview = await executor.preview(call);
      expect(preview.detail, contains('（含新建 2 个动作）'));

      // 确认期间，别处已经建好了其中一个
      exercise.rows
          .add(const ExerciseEntity(id: 7, name: '开合跳', category: 'cardio'));

      final result = await _executeJson(executor, call);
      expect(result['created_exercises'], ['提膝下压'],
          reason: '实际只建 1 个：预览的 2 个是当时快照，执行以最新库为准');
      expect(exercise.rows.where((e) => e.name == '开合跳'), hasLength(1),
          reason: '绝不允许因为预览报了 2 个就硬建 2 个');
      final ids =
          template.created.single.items.map((e) => e.exerciseId).toList();
      expect(ids, [7, exercise.rows.last.id]);
    });
  });
}

// ═══════════════════════ 测试辅助 ═══════════════════════

/// 默认动作库：深蹲 / 平板支撑
const _seed = <ExerciseEntity>[
  ExerciseEntity(id: 1, name: '深蹲', category: 'gym', muscleGroup: '腿部'),
  ExerciseEntity(id: 2, name: '平板支撑', category: 'bodyweight', muscleGroup: '核心'),
];

/// 构造一条 create_template 调用（[createMissing] 原样塞进 JSON，便于测字符串取值）
AiToolCall _templateCall(
  List<Map<String, dynamic>> items, {
  Object? createMissing,
}) =>
    AiToolCall(
      id: 'call_tpl_${items.length}',
      name: AiToolSpecs.createTemplate,
      argumentsJson: jsonEncode({
        'name': '下肢力量',
        'difficulty': '中阶',
        'focus': '全身',
        'minutes': 30,
        'items': items,
        if (createMissing != null) 'create_missing_exercises': createMissing,
      }),
    );

/// 构造一条 create_exercises 调用
AiToolCall _exercisesCall(List<Map<String, dynamic>> exercises) => AiToolCall(
      id: 'call_batch_${exercises.length}',
      name: AiToolSpecs.createExercises,
      argumentsJson: jsonEncode({'exercises': exercises}),
    );

/// 断言调用被拦下，且错误文案包含 [mentions]
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

/// 执行工具并把结果解析成 Map
Future<Map<String, dynamic>> _executeJson(
    AiToolExecutor executor, AiToolCall call) async {
  final raw = await executor.execute(call);
  return jsonDecode(raw) as Map<String, dynamic>;
}

/// 只用可变动作库 / 可变模板仓储时构造的仓储集合
AiToolRepos _repos({
  _MemoryExerciseRepo? exercise,
  _MemoryTemplateRepo? template,
}) =>
    AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
      database: fakeDatabase(),
      body: const _UntouchedBodyRepo(),
      water: const _UntouchedWaterRepo(),
      workout: const _UntouchedWorkoutRepo(),
      diet: const _UntouchedDietRepo(),
      goal: const _UntouchedGoalRepo(),
      settings: const _UntouchedSettingsRepo(),
      exercise: exercise ?? _MemoryExerciseRepo(_seed),
      template: template ?? _MemoryTemplateRepo(),
    );

// ═══════════ 内存版仓储（不碰数据库） ═══════════

/// 可变动作库：create / saveDefaults 真的写进内存（新 id 从 100 起，便于断言）
class _MemoryExerciseRepo implements ExerciseRepository {
  _MemoryExerciseRepo([List<ExerciseEntity> seed = const []]) {
    rows.addAll(seed);
  }

  final List<ExerciseEntity> rows = <ExerciseEntity>[];

  /// 每次 create 的动作名，用于断言「一个字都没写库」
  final List<String> createCalls = <String>[];

  int _nextId = 100;

  /// 当前库内动作名（用于比较调用前后是否一致）
  List<String> get names => rows.map((e) => e.name).toList();

  @override
  Future<List<ExerciseEntity>> getAll() async => List<ExerciseEntity>.of(rows);

  @override
  Future<List<ExerciseEntity>> getByCategory(String category) async =>
      rows.where((e) => e.category == category).toList();

  @override
  Future<ExerciseEntity?> getById(int id) async {
    for (final e in rows) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<List<ExerciseEntity>> search(String query) async {
    final q = query.trim().toLowerCase();
    return rows.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<ExerciseEntity> create(
      String name, String category, String? muscleGroup) async {
    createCalls.add(name);
    final entity = ExerciseEntity(
      id: _nextId++,
      name: name,
      category: category,
      muscleGroup: muscleGroup,
      isCustom: true,
    );
    rows.add(entity);
    return entity;
  }

  @override
  Future<void> update(ExerciseEntity exercise) async {
    final i = rows.indexWhere((e) => e.id == exercise.id);
    if (i >= 0) rows[i] = exercise;
  }

  @override
  Future<void> delete(int id) async {
    rows.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> saveDefaults(int id,
      {int? defaultReps,
      double? defaultWeightKg,
      int? defaultDurationSec}) async {
    final i = rows.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = rows[i];
    rows[i] = ExerciseEntity(
      id: old.id,
      name: old.name,
      category: old.category,
      muscleGroup: old.muscleGroup,
      isCustom: old.isCustom,
      defaultReps: defaultReps ?? old.defaultReps,
      defaultWeightKg: defaultWeightKg ?? old.defaultWeightKg,
      defaultDurationSec: defaultDurationSec ?? old.defaultDurationSec,
    );
  }
}

/// 可变模板仓储：只记录写入结果
class _MemoryTemplateRepo implements WorkoutTemplateRepository {
  /// 每次 create 的落库内容（顺序即调用顺序）
  final List<_CreatedTemplate> created = <_CreatedTemplate>[];

  @override
  Future<List<WorkoutTemplateEntity>> getAll() async => const [];

  @override
  Future<WorkoutTemplateEntity?> getById(int id) async => null;

  @override
  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    String type = 'strength',
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    created.add(_CreatedTemplate(name: name, items: items));
    return created.length;
  }

  @override
  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    String type = 'strength',
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {}

  @override
  Future<void> delete(int id) async {}
}

/// 一次 create 调用的落库结果
class _CreatedTemplate {
  const _CreatedTemplate({required this.name, required this.items});

  final String name;
  final List<TemplateItemInput> items;
}

// ═══════════ 不该被碰到的仓储（动作 / 模板写入不该访问它们） ═══════════

class _UntouchedBodyRepo implements BodyMetricRepository {
  const _UntouchedBodyRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 body 仓储');
}

class _UntouchedWaterRepo implements WaterRepository {
  const _UntouchedWaterRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 water 仓储');
}

class _UntouchedWorkoutRepo implements WorkoutRepository {
  const _UntouchedWorkoutRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 workout 仓储');
}

class _UntouchedDietRepo implements DietRepository {
  const _UntouchedDietRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 diet 仓储');
}

class _UntouchedGoalRepo implements GoalRepository {
  const _UntouchedGoalRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 goal 仓储');
}

class _UntouchedSettingsRepo implements UserSettingsRepository {
  const _UntouchedSettingsRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('动作 / 模板写入不该访问 settings 仓储');
}
