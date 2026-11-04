import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

/// 「再练一次」：把一条历史记录还原成待开练的动作清单（T15）。
///
/// **绝不预填重量**。这不是懒，是刻意：
/// - 预填重量 → 用户照着上次的重量练，上次能做不代表这次能做（受伤）
/// - 预填重量 → 用户直接一路点"完成"，记录变成假数据（数据造假）
/// 两个坑的共同源头都是"帮用户填好"。所以这里连字段都不写。
abstract final class WorkoutRepeat {
  /// 按 exerciseId 分组；组数 = 该动作出现过的组数；
  /// 次数 / 时长取该动作的**众数**（并列取较大值 —— 宁可多做一个，也不要少做）。
  ///
  /// [exerciseNames] / [exerciseCategories] 来自动作库；查不到时用兜底值，
  /// 不能让"动作被删了"导致整条记录不能重练。
  static List<ExerciseSlot> slotsOf(
    WorkoutEntity workout,
    Map<int, String> exerciseNames,
    Map<int, String> exerciseCategories,
  ) {
    if (workout.sets.isEmpty) return const [];

    // 按动作分组（保持首次出现顺序：用户上次的练法顺序值得保留）
    final order = <int>[];
    final grouped = <int, List<WorkoutSetEntity>>{};
    for (final set in workout.sets) {
      if (!grouped.containsKey(set.exerciseId)) {
        order.add(set.exerciseId);
        grouped[set.exerciseId] = [];
      }
      grouped[set.exerciseId]!.add(set);
    }

    return [
      for (final exerciseId in order)
        ExerciseSlot(
          exerciseId: exerciseId,
          exerciseName: exerciseNames[exerciseId] ?? '动作',
          category: exerciseCategories[exerciseId] ?? 'strength',
          targetSets: grouped[exerciseId]!.length,
          targetReps: _modeOf(
            grouped[exerciseId]!.map((s) => s.reps).whereType<int>(),
          ),
          targetDurationSec: _modeOf(
            grouped[exerciseId]!.map((s) => s.durationSec).whereType<int>(),
          ),
          // ⚠️ targetWeightKg 不出现在这里，一行注释就是这条规则的守卫（T15）
        ),
    ];
  }

  /// 众数；并列时取较大值；空集合返回 null
  static int? _modeOf(Iterable<int> values) {
    if (values.isEmpty) return null;
    final counts = <int, int>{};
    for (final v in values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    var best = values.first;
    var bestCount = 0;
    counts.forEach((value, count) {
      if (count > bestCount || (count == bestCount && value > best)) {
        best = value;
        bestCount = count;
      }
    });
    return best;
  }
}
