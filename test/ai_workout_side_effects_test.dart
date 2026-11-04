import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_side_effects.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

/// AI 写训练后，记录页数据源（workoutHistoryProvider）必须被失效。
/// 回归点：用户报「嘎教练说记好了，但记录页看不到」——根因就是副作用里漏了训练历史。
late AiToolCall _currentCall;

final _sideEffectProbe = Provider<Object?>((ref) {
  applyAiToolSideEffects(ref, _currentCall);
  return null;
});

void main() {
  test('log_workout 之后 workoutHistoryProvider 能读到新数据', () async {
    final repo = _MutableWorkoutRepo();
    final container =
        ProviderContainer(overrides: [workoutRepoProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);

    expect(await container.read(workoutHistoryProvider.future), isEmpty);

    // 模拟教练 log_workout 写库成功 → 库里多了一条
    repo.rows = [
      WorkoutEntity(
        id: 1,
        date: DateTime.now(),
        type: '力量',
        durationSec: 1800,
      ),
    ];
    _currentCall = const AiToolCall(
        id: 'c1', name: AiToolSpecs.logWorkout, argumentsJson: '{}');
    container.read(_sideEffectProbe);

    final after = await container.read(workoutHistoryProvider.future);
    expect(after, hasLength(1), reason: 'log_workout 后训练历史必须失效重拉，否则看不到新记录');
  });

  test('delete_workout / delete_records(workout) 同样失效训练历史', () async {
    for (final call in const [
      AiToolCall(
          id: 'c2',
          name: AiToolSpecs.deleteWorkout,
          argumentsJson: '{"workout_id":1}'),
      AiToolCall(
          id: 'c3',
          name: AiToolSpecs.deleteRecords,
          argumentsJson: '{"type":"workout"}'),
    ]) {
      final repo = _MutableWorkoutRepo()
        ..rows = [
          WorkoutEntity(
              id: 1, date: DateTime.now(), type: '力量', durationSec: 1800),
        ];
      final container = ProviderContainer(
          overrides: [workoutRepoProvider.overrideWithValue(repo)]);
      addTearDown(container.dispose);

      expect(await container.read(workoutHistoryProvider.future), hasLength(1));

      // 模拟删库成功 → 库里清空
      repo.rows = [];
      _currentCall = call;
      container.read(_sideEffectProbe);

      expect(await container.read(workoutHistoryProvider.future), isEmpty,
          reason: '${call.name} 后训练历史必须失效重拉，否则还显示已删的记录');
    }
  });
}

class _MutableWorkoutRepo implements WorkoutRepository {
  List<WorkoutEntity> rows = [];

  @override
  Future<List<WorkoutEntity>> getAll({DateTime? from, DateTime? to}) async =>
      rows;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
