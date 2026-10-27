import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 只读工具：query_stats / search_food（无需用户确认，直接执行）
class AiToolReaders extends AiToolHandler {
  const AiToolReaders(super.repos);

  /// 搜索结果最多回传条数（避免把整张表塞进上下文）
  static const maxSearchResults = 8;

  @override
  Set<String> get toolNames =>
      const {AiToolSpecs.queryStats, AiToolSpecs.searchFood};

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
      default:
        unsupported(call);
    }
  }

  static String _rangeLabel(String range) => switch (range) {
        'week' => '本周',
        'month' => '本月',
        _ => '全部',
      };

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
    });
  }
}
