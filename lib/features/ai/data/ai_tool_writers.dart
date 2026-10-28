import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 记录类写操作：log_weight / log_water / log_food / log_workout / log_measurements
class AiToolWriters extends AiToolHandler {
  const AiToolWriters(super.repos);

  static const _aiNote = 'AI 教练记录';

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.logWeight,
        AiToolSpecs.logWater,
        AiToolSpecs.logFood,
        AiToolSpecs.logWorkout,
        AiToolSpecs.logMeasurements,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.logWeight:
        final args = call.arguments;
        final jin = AiToolArgs.weightJin(args);
        final date = AiToolArgs.date(args);
        return AiToolPreview(
          call: call,
          label: '记录体重',
          detail: '${AiToolFormat.jin(jin)} 斤 · ${AiToolArgs.dateLabel(date)}',
          needsConfirm: true,
        );

      case AiToolSpecs.logWater:
        final cups = AiToolArgs.cups(call.arguments);
        return AiToolPreview(
          call: call,
          label: '记录饮水',
          detail: '今天共 $cups 杯（约 ${cups * 200} ml）',
          needsConfirm: true,
        );

      case AiToolSpecs.logFood:
        final args = call.arguments;
        final name = AiToolArgs.foodName(args);
        final grams = AiToolArgs.grams(args);
        final cal = AiToolArgs.caloriesPer100g(args);
        final meal = AiToolArgs.mealType(args);
        final kcal = cal * grams / 100;
        return AiToolPreview(
          call: call,
          label: '记录饮食',
          detail: '$name ${grams.round()}g · ${AiToolArgs.mealLabels[meal]}'
              ' · 约 ${kcal.round()} 千卡',
          needsConfirm: true,
        );

      case AiToolSpecs.logWorkout:
        final args = call.arguments;
        final type = AiToolArgs.workoutType(args);
        final minutes = AiToolArgs.minutes(args);
        final note = AiToolArgs.workoutNote(args);
        return AiToolPreview(
          call: call,
          label: '记录训练',
          detail: '$type训练 · $minutes 分钟${note != null ? ' · $note' : ''}',
          needsConfirm: true,
        );

      case AiToolSpecs.logMeasurements:
        final args = call.arguments;
        final m = AiToolArgs.measurements(args);
        final weightKg = AiToolArgs.optionalWeightKg(args);
        final date = AiToolArgs.date(args);
        final parts = <String>[
          m.label,
          if (weightKg != null) '体重 ${AiToolFormat.jinFromKg(weightKg)} 斤',
          AiToolArgs.dateLabel(date),
        ];
        return AiToolPreview(
          call: call,
          label: '记录围度',
          detail: parts.join(' · '),
          needsConfirm: true,
        );

      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.logWeight:
        return _logWeight(call);
      case AiToolSpecs.logWater:
        return _logWater(call);
      case AiToolSpecs.logFood:
        return _logFood(call);
      case AiToolSpecs.logWorkout:
        return _logWorkout(call);
      case AiToolSpecs.logMeasurements:
        return _logMeasurements(call);
      default:
        unsupported(call);
    }
  }

  Future<String> _logWeight(AiToolCall call) async {
    final args = call.arguments;
    final weightKg = AiToolArgs.weightKg(args);
    final date = AiToolArgs.date(args);
    await repos.body.create(date: date, weightKg: weightKg, note: _aiNote);
    return jsonEncode({
      'ok': true,
      'saved': {
        'weight_jin': AiToolFormat.jinFromKg(weightKg),
        'date': AiToolFormat.ymd(date),
      },
    });
  }

  Future<String> _logWater(AiToolCall call) async {
    final cups = AiToolArgs.cups(call.arguments);
    await repos.water.setTodayCups(cups);
    return jsonEncode({'ok': true, 'cups': cups, 'ml': cups * 200});
  }

  Future<String> _logFood(AiToolCall call) async {
    final args = call.arguments;
    final name = AiToolArgs.foodName(args);
    final grams = AiToolArgs.grams(args);
    final cal = AiToolArgs.caloriesPer100g(args);
    final meal = AiToolArgs.mealType(args);
    // 三大营养素可选：模型估不出来就是 null（写库为 NULL → UI 显示「—」）
    final protein = AiToolArgs.optionalProteinPer100g(args);
    final fat = AiToolArgs.optionalFatPer100g(args);
    final carbs = AiToolArgs.optionalCarbsPer100g(args);
    // 食物库有同名就用现成的，没有则按模型估算值新建自定义食物
    //
    // 命中现成食物时不传宏量、也不覆盖它已有的宏量：库里的数据比模型估的更可信。
    var food = await repos.diet.findFoodByName(name);
    var created = false;
    if (food == null) {
      final id = await repos.diet.addCustomFood(
        name: name,
        caloriesPer100g: cal,
        proteinPer100g: protein,
        fatPer100g: fat,
        carbsPer100g: carbs,
      );
      food = await repos.diet.getFoodById(id);
      created = true;
    }
    if (food == null) throw const AiToolException('食物写入失败');
    final now = DateTime.now();
    await repos.diet.addLog(
      date: now,
      foodId: food.id,
      grams: grams,
      mealType: meal,
    );
    // 三项齐备才算"这顿的营养是已知的"
    final macrosKnown = food.proteinPer100g != null &&
        food.fatPer100g != null &&
        food.carbsPer100g != null;
    return jsonEncode({
      'ok': true,
      'food': food.name,
      'grams': grams,
      'meal_type': meal,
      'kcal_estimated': (food.caloriesPer100g * grams / 100).round(),
      'new_food_created': created,
      'macros_known': macrosKnown,
      if (!macrosKnown)
        'macro_note': '这顿的三大营养素是未知的（蛋白 / 脂肪 / 碳水显示不出来），'
            '不要对用户说它们是多少，只说热量就行',
    });
  }

  Future<String> _logWorkout(AiToolCall call) async {
    final args = call.arguments;
    final type = AiToolArgs.workoutType(args);
    final minutes = AiToolArgs.minutes(args);
    final note = AiToolArgs.workoutNote(args);
    final now = DateTime.now();
    await repos.workout.createWorkout(
      date: now,
      type: type,
      note: note ?? _aiNote,
      durationSec: minutes * 60,
      sets: const [],
    );
    return jsonEncode({
      'ok': true,
      'type': type,
      'minutes': minutes,
      'date': AiToolFormat.ymd(now),
    });
  }

  /// 围度记录：体重缺省时取最新一次体重（没有体重记录则要求先记体重）
  Future<String> _logMeasurements(AiToolCall call) async {
    final args = call.arguments;
    final m = AiToolArgs.measurements(args);
    final date = AiToolArgs.date(args);
    var weightKg = AiToolArgs.optionalWeightKg(args);
    if (weightKg == null) {
      final latest = await repos.body.getLatest();
      if (latest == null) {
        throw const AiToolException('还没有体重记录，先记录一次体重');
      }
      weightKg = latest.weightKg;
    }
    await repos.body.create(
      date: date,
      weightKg: weightKg,
      waistCm: m.waistCm,
      hipCm: m.hipCm,
      chestCm: m.chestCm,
      note: _aiNote,
    );
    return jsonEncode({
      'ok': true,
      'date': AiToolFormat.ymd(date),
      'weight_jin': AiToolFormat.jinFromKg(weightKg),
      'waist_cm': m.waistCm,
      'hip_cm': m.hipCm,
      'chest_cm': m.chestCm,
    });
  }
}
