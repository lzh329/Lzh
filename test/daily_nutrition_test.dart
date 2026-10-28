import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/diet/data/diet_repository_impl.dart';

/// A2 用：每 100g = 27 kcal / 2.5 蛋白 / 0.3 脂肪 / 4.8 碳水
Future<int> addFood(
  AppDatabase db, {
  required String name,
  double calories = 27,
  double? protein = 2.5,
  double? fat = 0.3,
  double? carbs = 4.8,
}) {
  return db.into(db.foodLibrary).insert(FoodLibraryCompanion.insert(
        name: name,
        caloriesPer100g: calories,
        proteinPer100g: Value(protein),
        fatPer100g: Value(fat),
        carbsPer100g: Value(carbs),
        category: 'other',
      ));
}

Future<void> addLog(
  AppDatabase db, {
  required int foodId,
  required double grams,
  DateTime? date,
}) {
  final day = date ?? DateTime(2025, 3, 4);
  return db.into(db.foodLog).insert(FoodLogCompanion.insert(
        date: DateTime(day.year, day.month, day.day, 12),
        foodId: foodId,
        grams: grams,
        mealType: 'lunch',
      ));
}

void main() {
  late AppDatabase db;
  late DietRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = DietRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  final day = DateTime(2025, 3, 4);

  group('DailyNutrition 三态口径', () {
    test('A1 空日：calories == 0、宏量全 null、coverage == 0', () async {
      final n = await repo.getDailyNutrition(day);
      expect(n.calories, 0);
      expect(n.proteinG, isNull);
      expect(n.fatG, isNull);
      expect(n.carbsG, isNull);
      expect(n.macroCoverage, 0);
      expect(n.logCount, 0);
      expect(n.hasNoMacroData, isFalse, reason: '没有条目就不该说"这些记录没有营养数据"');
    });

    test('A2 全有：×200g 后热量 54、蛋白 5.0、coverage == 1', () async {
      final id = await addFood(db, name: '测试食物');
      await addLog(db, foodId: id, grams: 200);

      final n = await repo.getDailyNutrition(day);
      expect(n.calories, closeTo(54, 0.001));
      expect(n.proteinG, closeTo(5.0, 0.001));
      expect(n.fatG, closeTo(0.6, 0.001));
      expect(n.carbsG, closeTo(9.6, 0.001));
      expect(n.macroCoverage, 1);
      expect(n.isComplete, isTrue);
      expect(n.isPartial, isFalse);
    });

    test('A3 全缺：宏量全 null、coverage == 0（绝不给 0）', () async {
      final id = await addFood(
        db,
        name: '无营养数据食物',
        calories: 100,
        protein: null,
        fat: null,
        carbs: null,
      );
      await addLog(db, foodId: id, grams: 100);

      final n = await repo.getDailyNutrition(day);
      expect(n.calories, closeTo(100, 0.001), reason: '热量仍然算得出');
      expect(n.proteinG, isNull, reason: '0 代表"真的是 0"，缺失必须是 null');
      expect(n.fatG, isNull);
      expect(n.carbsG, isNull);
      expect(n.macroCoverage, 0);
      expect(n.hasNoMacroData, isTrue);
    });

    test('A4 混合：只加有值那条、coverage == 0.5、isPartial', () async {
      final withMacros = await addFood(db, name: '有营养');
      final withoutMacros = await addFood(
        db,
        name: '没营养',
        protein: null,
        fat: null,
        carbs: null,
      );
      await addLog(db, foodId: withMacros, grams: 200); // 蛋白 5.0
      await addLog(db, foodId: withoutMacros, grams: 100);

      final n = await repo.getDailyNutrition(day);
      expect(n.proteinG, closeTo(5.0, 0.001), reason: '只加有值那条，不能把缺的当 0 摊进去');
      expect(n.macroCoverage, 0.5);
      expect(n.logCount, 2);
      expect(n.macroLogCount, 1);
      expect(n.isPartial, isTrue);
      expect(n.isComplete, isFalse);
      expect(n.hasNoMacroData, isFalse);
    });

    test('A4b 部分记录里只有蛋白有值 → 该条不算"有宏量"（三项齐备才算）', () async {
      final partial = await addFood(
        db,
        name: '只有蛋白',
        protein: 10,
        fat: null,
        carbs: null,
      );
      await addLog(db, foodId: partial, grams: 100);

      final n = await repo.getDailyNutrition(day);
      expect(n.macroLogCount, 0, reason: '三项齐备才算有营养数据');
      expect(n.macroCoverage, 0);
      expect(n.proteinG, isNull);
    });

    test('A5 口径恒等：getDailyCalories == getDailyNutrition().calories', () async {
      // 空日
      expect(await repo.getDailyCalories(day),
          (await repo.getDailyNutrition(day)).calories);

      // 单条
      final id = await addFood(db, name: '食物A');
      await addLog(db, foodId: id, grams: 150);
      expect(await repo.getDailyCalories(day),
          (await repo.getDailyNutrition(day)).calories);

      // 多条
      await addLog(db, foodId: id, grams: 250);
      expect(await repo.getDailyCalories(day),
          (await repo.getDailyNutrition(day)).calories);
      expect(await repo.getDailyCalories(day), greaterThan(0));
    });

    test('A6 历史兼容：老记录宏量为 null 时不 backfill', () async {
      final id = await addFood(
        db,
        name: '老数据',
        protein: null,
        fat: null,
        carbs: null,
      );
      await addLog(db, foodId: id, grams: 100);

      final n = await repo.getDailyNutrition(day);
      expect(n.macroCoverage, 0);

      // 库里那行仍然是 null（没有反推写回）
      final row = await (db.select(db.foodLibrary)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.proteinPer100g, isNull);
      expect(row.fatPer100g, isNull);
      expect(row.carbsPer100g, isNull);
    });

    test('只统计当天（跨日不串）', () async {
      final id = await addFood(db, name: '食物B');
      await addLog(db, foodId: id, grams: 100, date: day);
      await addLog(db, foodId: id, grams: 900, date: DateTime(2025, 3, 5));

      final n = await repo.getDailyNutrition(day);
      expect(n.logCount, 1);
      expect(n.calories, closeTo(27, 0.001));
    });
  });

  group('A7 源码守卫：全 App 只有一个口径', () {
    late String impl;

    setUpAll(() {
      impl = File('lib/features/diet/data/diet_repository_impl.dart')
          .readAsStringSync();
    });

    test('getDailyCalories 是薄包装，函数体内不得有自己的 SQL / 求和循环', () {
      final start = impl.indexOf('Future<double> getDailyCalories(');
      expect(start, greaterThan(-1));
      final end =
          impl.indexOf('Future<DailyNutrition> getDailyNutrition(', start);
      final body = impl.substring(start, end);
      expect(body.contains('getDailyNutrition(date)'), isTrue);
      expect(body.contains('SUM('), isFalse);
      expect(body.contains('for ('), isFalse,
          reason: 'getDailyCalories 里再写一次求和 = 口径分叉');
    });

    test('宏量赋值不得出现 ?? 0（当初"按 0 计"的元凶）', () {
      final start = impl.indexOf('Future<DailyNutrition> getDailyNutrition(');
      final body = impl.substring(start);
      // 热量可以兜 0（它永远算得出）；宏量不行 —— 0 代表"真的是 0"
      final macroLines = body
          .split('\n')
          .where((String l) =>
              l.contains('protein_g') ||
              l.contains('fat_g') ||
              l.contains('carbs_g') ||
              l.contains('proteinG') ||
              l.contains('fatG') ||
              l.contains('carbsG'))
          .join('\n');
      expect(macroLines, isNotEmpty);
      expect(macroLines.contains('?? 0'), isFalse,
          reason: '宏量缺失必须是 null，不能被 0 兜底');
    });
  });
}
