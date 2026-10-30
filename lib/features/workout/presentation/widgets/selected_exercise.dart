import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 自定义训练里已选的一个动作（含计量方式）
class SelectedExercise {
  final ExerciseEntity exercise;
  final int targetSets;

  /// 力量动作的目标次数（有氧/静力为 null）
  final int? targetReps;

  /// 有氧/静力的目标时长（秒）；有氧在弹窗里按分钟填，这里换算成秒
  final int? targetDurationSec;

  const SelectedExercise({
    required this.exercise,
    required this.targetSets,
    this.targetReps,
    this.targetDurationSec,
  });

  /// 行内展示：力量 `深蹲 3 × 12` / 有氧 `跳绳 3 × 5 分钟` / 静力 `拉伸 3 × 45 秒`
  String get detail => setsDetail(
        category: exercise.category,
        sets: targetSets,
        reps: targetReps,
        durationSec: targetDurationSec ?? exercise.defaultDurationSec,
      );
}
