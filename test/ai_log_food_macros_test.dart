import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'fake_database.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// log_food 的三大营养素口径回归
///
/// 锁死三条不变量（外加解析层与提示词）：
/// 1. 带三项宏量 → 新建的自定义食物有宏量 → coverage == 1、proteinG != null
/// 2. 不带宏量 → coverage == 0、proteinG == **null**（绝不给 0）、hasNoMacroData
/// 3. 食物库已有同名食物 → 不覆盖它已有的宏量
/// 4. 解析层：缺失返回 null，0 只在真的是 0 时出现
/// 5. 提示词：要求模型估不出来就留空，别填 0
void main() {
  late AppDatabase db;
  late DietRepositoryImpl diet;
  late AiToolWriters writers;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    diet = DietRepositoryImpl(db);
    writers = AiToolWriters(_repos(diet));
  });

  tearDown(() async => db.close());

  /// 走一遍完整的 log_food：返回给模型的回执（已 jsonDecode）
  Future<Map<String, dynamic>> logFood(Map<String, dynamic> macros) async {
    final args = <String, dynamic>{
      'food_name': '牛肉面',
      'grams': 200,
      'meal_type': 'lunch',
      'calories_per_100g': 120,
      ...macros,
    };
    final call = AiToolCall(
      id: 'call-1',
      name: AiToolSpecs.logFood,
      argumentsJson: jsonEncode(args),
    );
    return jsonDecode(await writers.execute(call)) as Map<String, dynamic>;
  }

  /// 当日口径（log_food 按 DateTime.now() 落库）
  Future<dynamic> today() => diet.getDailyNutrition(DateTime.now());

  Future<Object?> foodRow(String name) async =>
      (db.select(db.foodLibrary)..where((t) => t.name.equals(name)))
          .getSingleOrNull();

  group('1. log_food 带三项宏量', () {
    test('新建的自定义食物有宏量 → coverage == 1、proteinG != null', () async {
      final receipt = await logFood({
        'protein_per_100g': 8,
        'fat_per_100g': 4,
        'carbs_per_100g': 15,
      });

      expect(receipt['ok'], isTrue);
      expect(receipt['new_food_created'], isTrue);
      expect(receipt['macros_known'], isTrue);
      expect(receipt.containsKey('macro_note'), isFalse);

      // 200g × 每 100g：蛋白 16 / 脂肪 8 / 碳水 30
      final n = await today();
      expect(n.macroCoverage, 1);
      expect(n.logCount, 1);
      expect(n.proteinG, closeTo(16, 0.001));
      expect(n.fatG, closeTo(8, 0.001));
      expect(n.carbsG, closeTo(30, 0.001));
      expect(n.hasNoMacroData, isFalse);
      expect(n.isComplete, isTrue);
    });

    test('库里那行确实是估的值（8/4/15），不是 0 也不是 null', () async {
      await logFood({
        'protein_per_100g': 8,
        'fat_per_100g': 4,
        'carbs_per_100g': 15,
      });

      final row = await foodRow('牛肉面');
      expect(row, isNotNull);
      final food = row as FoodLibraryData;
      expect(food.proteinPer100g, 8);
      expect(food.fatPer100g, 4);
      expect(food.carbsPer100g, 15);
    });
  });

  group('2. log_food 不带宏量', () {
    test('coverage == 0、宏量全 null、hasNoMacroData', () async {
      final receipt = await logFood(const {});

      expect(receipt['ok'], isTrue);
      expect(receipt['new_food_created'], isTrue);
      expect(receipt['macros_known'], isFalse);
      expect(receipt['macro_note'], isA<String>(), reason: '宏量未知时必须提示模型别编造');

      final n = await today();
      expect(n.calories, closeTo(240, 0.001), reason: '热量照样算得出');
      expect(n.macroCoverage, 0);
      expect(n.proteinG, isNull, reason: '0 代表"真的是 0"，缺失必须是 null');
      expect(n.fatG, isNull);
      expect(n.carbsG, isNull);
      expect(n.hasNoMacroData, isTrue);
    });

    test('库里那行是 NULL，没有被 0 兜底', () async {
      await logFood(const {});

      final row = await foodRow('牛肉面');
      expect(row, isNotNull);
      final food = row as FoodLibraryData;
      expect(food.proteinPer100g, isNull);
      expect(food.fatPer100g, isNull);
      expect(food.carbsPer100g, isNull);
    });

    test('只给了蛋白（三项不齐）→ 仍按"未知"处理，不写半个宏量进去', () async {
      final receipt = await logFood({'protein_per_100g': 8});

      expect(receipt['macros_known'], isFalse);
      final n = await today();
      expect(n.macroCoverage, 0);
      expect(n.proteinG, isNull, reason: '三项齐备才算"已知"');
    });

    test('预览卡不编造宏量：只有热量，不出现蛋白 / 脂肪 / 碳水数字', () async {
      final call = AiToolCall(
        id: 'call-1',
        name: AiToolSpecs.logFood,
        argumentsJson: jsonEncode({
          'food_name': '牛肉面',
          'grams': 200,
          'meal_type': 'lunch',
          'calories_per_100g': 120,
        }),
      );
      final preview = await writers.preview(call);
      expect(preview.detail, contains('约 240 千卡'));
      expect(preview.detail, isNot(contains('蛋白')));
      expect(preview.detail, isNot(contains('脂肪')));
      expect(preview.detail, isNot(contains('碳水')));
    });
  });

  group('3. 食物库已有同名食物', () {
    test('不覆盖它已有的宏量（模型估算值再高也不写进去）', () async {
      await _seedFood(db, name: '牛肉面', protein: 5, fat: 1, carbs: 10);

      final receipt = await logFood({
        'protein_per_100g': 99,
        'fat_per_100g': 99,
        'carbs_per_100g': 99,
      });

      expect(receipt['new_food_created'], isFalse);
      // 200g × 库里的 5/1/10 → 10 / 2 / 20
      final n = await today();
      expect(n.proteinG, closeTo(10, 0.001));
      expect(n.fatG, closeTo(2, 0.001));
      expect(n.carbsG, closeTo(20, 0.001));
      expect(n.macroCoverage, 1);

      final food = await foodRow('牛肉面') as FoodLibraryData;
      expect(food.proteinPer100g, 5);
      expect(food.fatPer100g, 1);
      expect(food.carbsPer100g, 10);
    });

    test('库里那条本来就没宏量 → 模型给了也不补，仍然显示「—」', () async {
      await _seedFood(db, name: '牛肉面', protein: null, fat: null, carbs: null);

      final receipt = await logFood({
        'protein_per_100g': 8,
        'fat_per_100g': 4,
        'carbs_per_100g': 15,
      });

      expect(receipt['new_food_created'], isFalse);
      expect(receipt['macros_known'], isFalse);
      final n = await today();
      expect(n.macroCoverage, 0);
      expect(n.proteinG, isNull);

      final food = await foodRow('牛肉面') as FoodLibraryData;
      expect(food.proteinPer100g, isNull, reason: '现成食物库数据更可信，不拿估算值覆盖');
    });
  });

  group('4. 解析层：可选宏量', () {
    test('缺失 / 空串返回 null，绝不返回 0', () {
      expect(
          AiToolArgs.optionalProteinPer100g(const <String, dynamic>{}), isNull);
      expect(
          AiToolArgs.optionalFatPer100g(<String, dynamic>{'fat_per_100g': ''}),
          isNull);
      expect(
          AiToolArgs.optionalCarbsPer100g(
              <String, dynamic>{'carbs_per_100g': '  '}),
          isNull);
    });

    test('字符串数字照收；真的是 0 就返回 0（0 是"真的是 0"）', () {
      expect(
          AiToolArgs.optionalProteinPer100g(
              <String, dynamic>{'protein_per_100g': '8.5'}),
          8.5);
      expect(
          AiToolArgs.optionalFatPer100g(<String, dynamic>{'fat_per_100g': 0}),
          0);
      expect(
          AiToolArgs.optionalCarbsPer100g(
              <String, dynamic>{'carbs_per_100g': 0}),
          0);
    });

    test('越界 / 非法值抛异常（不静默截断成 0）', () {
      expect(
        () => AiToolArgs.optionalProteinPer100g(
            <String, dynamic>{'protein_per_100g': 200}),
        throwsA(isA<AiToolException>()),
      );
      expect(
        () => AiToolArgs.optionalCarbsPer100g(
            <String, dynamic>{'carbs_per_100g': '很多'}),
        throwsA(isA<AiToolException>()),
      );
    });
  });

  group('5. 提示词与工具契约', () {
    test('提示词要求：能估就给、估不出来留空别填 0', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('三大营养素'));
      expect(prompt, contains('估不出来就留空'));
      expect(prompt, contains('别填 0'));
    });

    test('log_food schema 里三个宏量是可选参数，不在 required 里', () {
      final def = AiToolSpecs.defs.firstWhere(
        (d) => (d['function'] as Map)['name'] == AiToolSpecs.logFood,
      );
      final params = (def['function'] as Map)['parameters'] as Map;
      final props = params['properties'] as Map;
      for (final key in const [
        'protein_per_100g',
        'fat_per_100g',
        'carbs_per_100g',
      ]) {
        expect(props.containsKey(key), isTrue, reason: '$key 要能被模型传进来');
      }
      final required = (params['required'] as List).cast<String>();
      expect(
        required,
        isNot(containsAll(const [
          'protein_per_100g',
          'fat_per_100g',
          'carbs_per_100g',
        ])),
      );
    });
  });
}

/// 往食物库塞一条（模拟"库里已经有这个食物"）
Future<int> _seedFood(
  AppDatabase db, {
  required String name,
  required double? protein,
  required double? fat,
  required double? carbs,
}) {
  return db.into(db.foodLibrary).insert(FoodLibraryCompanion.insert(
        name: name,
        caloriesPer100g: 120,
        proteinPer100g: Value(protein),
        fatPer100g: Value(fat),
        carbsPer100g: Value(carbs),
        category: 'other',
      ));
}

/// 只给 diet 真仓储，其余一律拦下（log_food 不该碰它们）
AiToolRepos _repos(DietRepositoryImpl diet) => AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
        database: fakeDatabase(),
      body: const _UntouchedBodyRepo(),
      water: const _UntouchedWaterRepo(),
      workout: const _UntouchedWorkoutRepo(),
      diet: diet,
      goal: const _UntouchedGoalRepo(),
      settings: const _UntouchedSettingsRepo(),
      exercise: const _UntouchedExerciseRepo(),
      template: const _UntouchedTemplateRepo(),
    );

class _UntouchedBodyRepo implements BodyMetricRepository {
  const _UntouchedBodyRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 body 仓储');
}

class _UntouchedWaterRepo implements WaterRepository {
  const _UntouchedWaterRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 water 仓储');
}

class _UntouchedWorkoutRepo implements WorkoutRepository {
  const _UntouchedWorkoutRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 workout 仓储');
}

class _UntouchedGoalRepo implements GoalRepository {
  const _UntouchedGoalRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 goal 仓储');
}

class _UntouchedSettingsRepo implements UserSettingsRepository {
  const _UntouchedSettingsRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 settings 仓储');
}

class _UntouchedExerciseRepo implements ExerciseRepository {
  const _UntouchedExerciseRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 exercise 仓储');
}

class _UntouchedTemplateRepo implements WorkoutTemplateRepository {
  const _UntouchedTemplateRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('log_food 不该访问 template 仓储');
}
