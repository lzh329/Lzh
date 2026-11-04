import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/template_expansion.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart'
    show NewSetData;

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
        AiToolSpecs.updateWorkout,
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
        final exCount = AiToolArgs.workoutExercises(args).length;
        return AiToolPreview(
          call: call,
          label: '记录训练',
          detail: '$type训练 · $minutes 分钟'
              '${exCount > 0 ? ' · $exCount 个动作' : ''}'
              '${note != null ? ' · $note' : ''}',
          needsConfirm: true,
        );

      case AiToolSpecs.updateWorkout:
        final id = AiToolArgs.workoutId(call.arguments);
        final minutes = AiToolArgs.optionalMinutes(call.arguments);
        final exCount = AiToolArgs.workoutExercises(call.arguments).length;
        return AiToolPreview(
          call: call,
          label: '修改训练记录',
          detail: '#$id${exCount > 0 ? ' · $exCount 个动作' : ''}'
              '${minutes != null ? ' · 时长 $minutes 分钟' : ''}',
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
      case AiToolSpecs.updateWorkout:
        return _updateWorkout(call);
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
    var type = AiToolArgs.workoutType(args);
    var minutes = AiToolArgs.minutes(args);
    final note = AiToolArgs.workoutNote(args);
    final date = AiToolArgs.date(args);
    final templateName = AiToolArgs.optionalString(args['template_name']);

    // ── 按模板补记（优先路径）──
    // 组次/时长只有模板里是准的；让模型把模板口述成 exercises 会丢 targetReps/
    // targetDurationSec，真机上每组就变成"未记录"。
    String? matchedTemplate;
    List<NewSetData> sets;
    if (templateName != null) {
      final tpl = await _findTemplate(templateName);
      if (tpl == null) {
        throw AiToolException('没找到模板「$templateName」，先用 query_stats 看 templates 列表');
      }
      try {
        sets = expandTemplateSets(tpl);
      } on TemplateEmptyException catch (e) {
        throw AiToolException('$e，先编辑模板加点动作');
      }
      minutes = tpl.minutes;
      type = tpl.isCardio
          ? '有氧'
          : (tpl.items.any((i) => i.category == 'stretch') &&
                  !tpl.items.any((i) => i.category == 'strength')
              ? '拉伸'
              : '力量');
      matchedTemplate = tpl.name;
    } else {
      sets = await _resolveSets(AiToolArgs.workoutExercises(args));
    }

    final w = await repos.workout.createWorkout(
      date: date,
      type: type,
      note: note ?? _aiNote,
      durationSec: minutes * 60,
      sets: sets,
    );
    // 按动作聚合，让模型能原样复述"深蹲 4 组 × 12 次"
    final grouped = <int, Map<String, Object?>>{};
    for (final s in sets) {
      final e = grouped.putIfAbsent(
          s.exerciseId, () => {'name': null, 'sets': 0, 'reps': s.reps});
      e['sets'] = (e['sets'] as int) + 1;
    }
    if (matchedTemplate != null) {
      // 补上动作名，让模型能原样复述"深蹲 4 组 × 12 次"
      final tpl = await _findTemplate(matchedTemplate);
      if (tpl != null) {
        for (final item in tpl.items) {
          grouped[item.exerciseId]?['name'] = item.exerciseName;
        }
      }
      for (final e in grouped.values) {
        e['name'] ??= '动作';
      }
    }
    return jsonEncode({
      'ok': true,
      'workout_id': w.id,
      'type': type,
      'minutes': minutes,
      'date': AiToolFormat.ymd(date),
      'set_count': sets.length,
      'exercise_count': sets.map((s) => s.exerciseId).toSet().length,
      if (matchedTemplate != null) 'template': matchedTemplate,
      if (matchedTemplate != null) 'exercises': grouped.values.toList(),
    });
  }

  /// 按名字找模板：忽略大小写与首尾空格；找不到返回 null
  Future<WorkoutTemplateEntity?> _findTemplate(String name) async {
    final target = name.trim().toLowerCase();
    final all = await repos.template.getAll();
    for (final t in all) {
      if (t.name.trim().toLowerCase() == target) return t;
    }
    return null;
  }

  /// 修改一条训练记录（按 id）：整体替换动作清单，备注可留空保留原值
  Future<String> _updateWorkout(AiToolCall call) async {
    final args = call.arguments;
    final id = AiToolArgs.workoutId(args);
    final note = AiToolArgs.workoutNote(args);
    // 可选：模型只在用户明确要改时长时才传（不传 = 时长保持不变）
    final minutes = AiToolArgs.optionalMinutes(args);
    // 「没给动作」和「给了空数组」都当成**不动动作清单**：
    // 只改时长/备注是最常见的用法，而"0 个动作的训练"没有业务意义
    // （真要删整条记录请用 delete_workout）。
    final inputs = AiToolArgs.workoutExercises(args);
    final sets = inputs.isEmpty ? null : await _resolveSets(inputs);
    final existing = await repos.workout.getById(id);
    if (existing == null) {
      throw const AiToolException('没找到这条训练记录，先用 query_workouts 查一下 id');
    }
    await repos.workout.updateWorkout(
      id: id,
      note: note,
      durationSec: minutes == null ? null : minutes * 60,
      sets: sets,
    );
    // 回执里给"现在的时长/动作数"（改了就是新值，没改就是原值），模型据此复述
    final durationMinutes = minutes ??
        (existing.durationSec == null ? null : existing.durationSec! ~/ 60);
    final exerciseCount = sets == null
        ? existing.sets.map((s) => s.exerciseId).toSet().length
        : sets.map((s) => s.exerciseId).toSet().length;
    return jsonEncode({
      'ok': true,
      'workout_id': id,
      'exercise_count': exerciseCount,
      'duration_minutes': durationMinutes,
    });
  }

  /// 动作名 → id 映射，展开成 N 条 set（与「记一笔」同口径：一行动作 = N 组 × 组次重）
  ///
  /// 名字不在动作库 → 抛错，让模型先 query_exercises；不给动作则返回空列表
  /// （兼容"只记时长"的旧调用）。
  Future<List<NewSetData>> _resolveSets(
      List<AiWorkoutExerciseInput> inputs) async {
    if (inputs.isEmpty) return const [];
    final all = await repos.exercise.getAll();
    final byName = {
      for (final e in all) e.name.trim().toLowerCase(): e,
    };
    final sets = <NewSetData>[];
    for (final input in inputs) {
      final ex = byName[input.name.toLowerCase()];
      if (ex == null) {
        throw AiToolException('动作「${input.name}」不在动作库，先用 query_exercises 查一下');
      }
      // 兜底链：模型给的值 → 动作库默认值 → null（**不瞎编**）
      // 之前力量动作没传 reps 时直接写 null，有氧只看动作库默认（多为 null），
      // 用户补记后详情页每组的次数/时长全是"未记录"。
      final timed = ex.category == 'cardio' || ex.category == 'stretch';
      final reps = timed ? null : (input.reps ?? ex.defaultReps);
      final durationSec =
          timed ? (input.durationSec ?? ex.defaultDurationSec) : null;
      final weightKg = timed ? null : input.weightKg;
      for (var i = 1; i <= input.sets; i++) {
        sets.add(NewSetData(
          exerciseId: ex.id,
          setNumber: i,
          reps: reps,
          weightKg: weightKg,
          durationSec: durationSec,
          isWarmup: false,
        ));
      }
    }
    return sets;
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
