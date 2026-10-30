import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/presentation/pages/custom_workout_page.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 自定义训练按动作分类计量：展示文案 + 字段能带到会话
void main() {
  ExerciseEntity ex(String name, String category, {int? reps, int? dur}) =>
      ExerciseEntity(
        id: name.hashCode,
        name: name,
        category: category,
        defaultReps: reps,
        defaultDurationSec: dur,
      );

  test('力量动作：深蹲 3 × 12', () {
    final se = SelectedExercise(
      exercise: ex('深蹲', 'strength', reps: 12),
      targetSets: 3,
      targetReps: 12,
    );
    expect(se.detail, '3 × 12');
    expect('${se.exercise.name} ${se.detail}', '深蹲 3 × 12');
  });

  test('有氧动作：跳绳 3 × 5 分钟', () {
    final se = SelectedExercise(
      exercise: ex('跳绳', 'cardio'),
      targetSets: 3,
      targetDurationSec: 300,
    );
    expect(se.detail, '3 × 5 分钟');
    expect('${se.exercise.name} ${se.detail}', '跳绳 3 × 5 分钟');
  });

  test('拉伸动作：拉伸 3 × 45 秒', () {
    final se = SelectedExercise(
      exercise: ex('腿部拉伸', 'stretch'),
      targetSets: 3,
      targetDurationSec: 45,
    );
    expect(se.detail, '3 × 45 秒');
  });

  test('用户填的值能带到会话（不退回动作默认值）', () {
    final se = SelectedExercise(
      exercise: ex('深蹲', 'strength', reps: 10),
      targetSets: 4,
      targetReps: 15,
    );
    // 会话取的是 se.targetReps ?? default，这里是 15 而不是默认 10
    expect(se.targetReps ?? se.exercise.defaultReps, 15);
    expect(se.targetSets, 4);

    final cardio = SelectedExercise(
      exercise: ex('跳绳', 'cardio', dur: 60),
      targetSets: 2,
      targetDurationSec: 300,
    );
    expect(cardio.targetDurationSec ?? cardio.exercise.defaultDurationSec, 300,
        reason: '用户填 5 分钟就该是 300 秒，不是动作默认 60');
  });

  test('setsDetail 与 EditItem.detail 同一份规则（不出现两套）', () {
    expect(
      setsDetail(category: 'cardio', sets: 3, durationSec: 300),
      '3 × 5 分钟',
    );
    const item = EditItem(
        exerciseId: 1,
        name: 'x',
        category: 'cardio',
        sets: 3,
        durationSec: 300);
    expect(item.detail, '3 × 5 分钟');
  });
}
