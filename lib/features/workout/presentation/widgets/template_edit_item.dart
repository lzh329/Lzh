/// 新建/编辑模板时的一行动作（页面内部状态模型）
class EditItem {
  final int exerciseId;
  final String name;
  final String category;
  final int sets;
  final int? reps;
  final int? durationSec;

  const EditItem({
    required this.exerciseId,
    required this.name,
    required this.category,
    required this.sets,
    this.reps,
    this.durationSec,
  });

  EditItem copyWith({int? sets, int? reps, int? durationSec}) => EditItem(
        exerciseId: exerciseId,
        name: name,
        category: category,
        sets: sets ?? this.sets,
        reps: reps,
        durationSec: durationSec,
      );

  /// 「3 组 × 12 次」/「3 组 × 60 秒」
  String get detail =>
      reps != null ? '$sets 组 × $reps 次' : '$sets 组 × ${durationSec ?? 0} 秒';
}
