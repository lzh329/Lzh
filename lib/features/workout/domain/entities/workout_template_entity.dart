/// 训练模板实体（数据库化后）
class WorkoutTemplateEntity {
  final int id;
  final String name;
  final String difficulty; // 入门 / 中阶 / 高阶
  final String focus; // 全身 / 放松 / 碎片
  final int minutes;
  final String? description;
  final String accentKey; // green / orange / red / cyan / purple
  final bool isRecommended;
  final List<WorkoutTemplateItemEntity> items;

  const WorkoutTemplateEntity({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.focus,
    required this.minutes,
    this.description,
    this.accentKey = 'green',
    this.isRecommended = false,
    this.items = const [],
  });

  /// 动作预览文案，如 "深蹲 3×15 · 俯卧撑 3×10 · 平板支撑 3×30s"
  String get previewText => items
      .map((i) => i.targetReps != null
          ? '${i.exerciseName} ${i.targetSets}×${i.targetReps}'
          : '${i.exerciseName} ${i.targetSets}×${i.targetDurationSec}s')
      .join(' · ');
}

class WorkoutTemplateItemEntity {
  final int id;
  final int templateId;
  final int exerciseId;
  final String exerciseName;
  final String category;
  final int targetSets;
  final int? targetReps;
  final int? targetDurationSec;

  const WorkoutTemplateItemEntity({
    required this.id,
    required this.templateId,
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.targetSets,
    this.targetReps,
    this.targetDurationSec,
  });
}
