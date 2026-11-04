import '../entities/workout_entity.dart';

abstract class WorkoutRepository {
  Future<List<WorkoutEntity>> getAll({DateTime? from, DateTime? to});
  Future<WorkoutEntity?> getById(int id);
  Future<WorkoutEntity> createWorkout({
    required DateTime date,
    required String type,
    int? planId,
    String? note,
    int? durationSec,
    required List<NewSetData> sets,
  });
  /// 改一条训练记录。三个可选参数都是"不传 = 不动"：
  ///
  /// - [note] null = 不动备注；
  /// - [durationSec] null = 不动时长（时长是计时得来的，改动作不该顺手清空）；
  /// - [sets] null = **不动动作清单**（只改时长/备注时用）。
  ///
  /// ⚠️ `sets: []`（空列表）与 `null` 语义不同：`[]` 表示"把动作删光"。
  /// 但业务上"0 个动作的训练"没有意义，所以写工具会把空清单转成 null
  /// （要删除整条记录请用 delete_workout）。
  Future<void> updateWorkout({
    required int id,
    String? note,
    int? durationSec,
    List<NewSetData>? sets,
  });
  Future<void> delete(int id);
}

class NewSetData {
  final int exerciseId;
  final int setNumber;
  final int? reps;
  final double? weightKg;
  final int? durationSec;
  final bool isWarmup;

  const NewSetData({
    required this.exerciseId,
    required this.setNumber,
    this.reps,
    this.weightKg,
    this.durationSec,
    this.isWarmup = false,
  });
}
