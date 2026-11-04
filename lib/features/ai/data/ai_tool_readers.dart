import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

/// 只读工具：query_stats / search_food / query_exercises（无需用户确认，直接执行）
class AiToolReaders extends AiToolHandler {
  const AiToolReaders(super.repos);

  /// 搜索结果最多回传条数（避免把整张表塞进上下文）
  static const maxSearchResults = 8;

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.queryStats,
        AiToolSpecs.searchFood,
        AiToolSpecs.queryExercises,
        AiToolSpecs.queryWorkouts,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.queryStats:
        final range = AiToolArgs.range(call.arguments);
        return AiToolPreview(
          call: call,
          label: '查询统计',
          detail: _rangeLabel(range),
          needsConfirm: false,
        );
      case AiToolSpecs.searchFood:
        final query = AiToolArgs.searchQuery(call.arguments);
        return AiToolPreview(
          call: call,
          label: '搜索食物',
          detail: '搜索"$query"',
          needsConfirm: false,
        );
      case AiToolSpecs.queryExercises:
        final args = call.arguments;
        final query = AiToolArgs.optionalExerciseQuery(args);
        final category = AiToolArgs.optionalExerciseCategory(args);
        return AiToolPreview(
          call: call,
          label: '查动作库',
          detail: _exerciseDetail(query, category),
          needsConfirm: false,
        );
      case AiToolSpecs.queryWorkouts:
        return AiToolPreview(
          call: call,
          label: '查训练记录',
          detail: '最近 ${AiToolArgs.workoutCount(call.arguments)} 条',
          needsConfirm: false,
        );
      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.queryStats:
        return _queryStats(AiToolArgs.range(call.arguments));
      case AiToolSpecs.searchFood:
        return _searchFood(AiToolArgs.searchQuery(call.arguments));
      case AiToolSpecs.queryExercises:
        final args = call.arguments;
        return _queryExercises(
          query: AiToolArgs.optionalExerciseQuery(args),
          category: AiToolArgs.optionalExerciseCategory(args),
        );
      case AiToolSpecs.queryWorkouts:
        return _queryWorkouts(AiToolArgs.workoutCount(call.arguments));
      default:
        unsupported(call);
    }
  }

  static String _rangeLabel(String range) => switch (range) {
        'week' => '本周',
        'month' => '本月',
        _ => '全部',
      };

  /// 「搜索"深蹲"」/「查看动作库（器械）」/「查看动作库」
  static String _exerciseDetail(String? query, String? category) {
    if (query != null) return '搜索"$query"';
    if (category != null) {
      return '查看动作库（${AiExerciseCategories.labelOf(category)}）';
    }
    return '查看动作库';
  }

  /// 动作库查询：名称包含匹配（忽略大小写）+ 分类精确匹配，最多回传 8 条
  Future<String> _queryExercises({String? query, String? category}) async {
    final all = await repos.exercise.getAll();
    final keyword = query?.toLowerCase();
    final hits = all.where((e) {
      if (category != null && e.category != category) return false;
      if (keyword == null) return true;
      return e.name.toLowerCase().contains(keyword);
    }).take(maxSearchResults).toList();

    return jsonEncode({
      'ok': true,
      'query': query,
      'category': category,
      'count': hits.length,
      'results': [
        for (final e in hits)
          {
            'id': e.id,
            'name': e.name,
            'category': e.category,
            'muscle_group': e.muscleGroup,
            'default_reps': e.defaultReps,
            'default_duration_sec': e.defaultDurationSec,
          },
      ],
    });
  }

  Future<String> _searchFood(String query) async {
    final foods = await repos.diet.searchFoods(query: query);
    final hits = foods.take(maxSearchResults).toList();
    return jsonEncode({
      'ok': true,
      'query': query,
      'count': hits.length,
      'results': [
        for (final f in hits)
          {
            'name': f.name,
            'kcal_per_100g': f.caloriesPer100g.round(),
            'category': f.category,
          },
      ],
    });
  }

  Future<String> _queryStats(String range) async {
    final now = DateTime.now();
    DateTime from;
    switch (range) {
      case 'month':
        from = DateTime(now.year, now.month, 1);
      case 'all':
        from = DateTime(2000);
      default:
        from = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    }

    final metrics = await repos.body.getAll();
    final sorted = [...metrics]..sort((a, b) => a.date.compareTo(b.date));
    final workouts = await repos.workout.getAll();
    final rangeWorkouts =
        workouts.where((w) => !w.date.isBefore(from)).toList();
    final cups = await repos.water.getTodayCups();
    final calories = await repos.diet.getDailyCalories(now);
    final goals = await repos.goal.getAll();
    final templates = await repos.template.getAll();

    return jsonEncode({
      'range': range,
      'weight': {
        'latest_jin': sorted.isEmpty
            ? null
            : double.parse((sorted.last.weightKg * 2).toStringAsFixed(1)),
        'first_jin': sorted.isEmpty
            ? null
            : double.parse((sorted.first.weightKg * 2).toStringAsFixed(1)),
        'count': sorted.length,
        'latest_date': sorted.isEmpty ? null : AiToolFormat.ymd(sorted.last.date),
        'waist_cm': sorted.isEmpty ? null : sorted.last.waistCm,
        'hip_cm': sorted.isEmpty ? null : sorted.last.hipCm,
        'chest_cm': sorted.isEmpty ? null : sorted.last.chestCm,
      },
      'workouts': {
        'count': rangeWorkouts.length,
        'days': rangeWorkouts
            .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
            .toSet()
            .length,
        'minutes': rangeWorkouts.fold<int>(
            0, (sum, w) => sum + ((w.durationSec ?? 0) / 60).round()),
      },
      'water_cups_today': cups,
      'calories_today': calories.round(),
      // 目标列表：模型据此拿到 goal_id 再调用 manage_goal，不要猜 id
      'goals': [
        for (final g in goals)
          {
            'id': g.id,
            'type': g.type,
            'category': g.category,
            'target_value': g.targetValue,
            'current_value': g.currentValue,
            'completed': g.isCompleted,
          },
      ],
      // 模板清单：模型据此判断"有哪个模板可以直接开练"（start_workout 用），
      // 没有模板时也知道该建议用户新建，而不是瞎猜名字。
      // items 给全动作+组次：补记"模板里的训练"时模型要原样落库，不能只记个名。
      'templates': [
        for (final t in templates)
          {
            'id': t.id,
            'name': t.name,
            'focus': t.focus,
            'difficulty': t.difficulty,
            'minutes': t.minutes,
            'type': t.type,
            'type_label': t.typeLabel,
            'item_count': t.items.length,
            'items': [
              for (final i in t.items)
                {
                  'exercise_name': i.exerciseName,
                  'sets': i.targetSets,
                  'reps': i.targetReps,
                  'duration_sec': i.targetDurationSec,
                },
            ],
          },
      ],
    });
  }

  /// 最近的训练记录明细（改/删训练前先查这个拿 workout_id）
  Future<String> _queryWorkouts(int count) async {
    final workouts = await repos.workout.getAll();
    final sorted = [...workouts]..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(count).toList();
    final exercises = await repos.exercise.getAll();
    final exName = {for (final e in exercises) e.id: e.name};
    return jsonEncode({
      'ok': true,
      'count': recent.length,
      'workouts': [
        for (final w in recent)
          {
            'id': w.id,
            'date': AiToolFormat.ymd(w.date),
            'type': _workoutTypeLabel(w.type),
            'minutes': ((w.durationSec ?? 0) / 60).round(),
            'note': w.note,
            'exercises': _groupWorkoutSets(w.sets, exName),
          },
      ],
    });
  }

  /// 把一组 set 按动作聚合回「动作 × 组数 × 次数/重量」的紧凑形态
  List<Map<String, dynamic>> _groupWorkoutSets(
      List<WorkoutSetEntity> sets, Map<int, String> exName) {
    final byEx = <int, List<WorkoutSetEntity>>{};
    for (final s in sets) {
      byEx.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    return [
      for (final e in byEx.entries)
        {
          'name': exName[e.key] ?? '动作 #${e.key}',
          'sets': e.value.length,
          'reps': e.value.first.reps,
          'weight_kg': e.value.first.weightKg,
          'duration_sec': e.value.first.durationSec,
        },
    ];
  }

  /// 内部 type（free / plan / log / 力量…）→ 给人看的类型
  ///
  /// `log`（事后补记）要说成「补记」：模型看到 log 会自己发挥，看到补记才知道
  /// "这条没有计时、可能是回忆的"。
  String _workoutTypeLabel(String type) {
    if (type == 'log') return '补记';
    const known = {'力量', '有氧', '拉伸', '其他'};
    return known.contains(type) ? type : '训练';
  }
}
