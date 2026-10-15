import 'package:flutter_test/flutter_test.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

void main() {
  group('ExerciseEntity', () {
    test('should create exercise with required fields', () {
      final exercise = ExerciseEntity(id: 1, name: '俯卧撑', category: 'bodyweight', muscleGroup: '胸部');
      expect(exercise.id, 1);
      expect(exercise.name, '俯卧撑');
      expect(exercise.category, 'bodyweight');
      expect(exercise.muscleGroup, '胸部');
      expect(exercise.isCustom, false);
    });
  });

  group('WorkoutEntity', () {
    test('should calculate total sets and completed sets', () {
      final sets = [
        const WorkoutSetEntity(id: 1, workoutId: 1, exerciseId: 1, setNumber: 1, reps: 10),
        const WorkoutSetEntity(id: 2, workoutId: 1, exerciseId: 1, setNumber: 2, reps: 8),
        const WorkoutSetEntity(id: 3, workoutId: 1, exerciseId: 2, setNumber: 1, reps: 12, isCompleted: false),
      ];
      final workout = WorkoutEntity(id: 1, date: DateTime(2025, 5, 31), type: 'free', sets: sets);
      expect(workout.totalSets, 3);
      expect(workout.completedSets, 2);
    });
  });

  group('BodyMetricEntity', () {
    test('should create body metric with optional fields', () {
      final metric = BodyMetricEntity(id: 1, date: DateTime(2025, 5, 31), weightKg: 75.5, waistCm: 82.0, note: '早晨空腹');
      expect(metric.weightKg, 75.5);
      expect(metric.waistCm, 82.0);
      expect(metric.hipCm, isNull);
      expect(metric.note, '早晨空腹');
    });
  });
}
