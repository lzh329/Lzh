import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart'
    show NewSetData;

/// 「记一笔」的录入模型 —— **纯数据 + 纯函数**，不碰 UI 也不碰 DB。
///
/// 为什么单独立一个文件：这个模块的价值全在"模板 → 实际组次重 → workouts/workout_sets"
/// 的转换上。转换是纯函数就能单测（不需要 pump 界面、不需要内存库），
/// 界面只是它的编辑器。
///
/// 口径（与教练/开练流程保持一致）：
/// - 一个动作填一套「组数 × 次数 × 重量」（**不做逐组差异**：补记是回忆，
///   想逐组记不同重量的人应该去开练页；这里多一层编辑器只会让人放弃记录）
/// - 落下 N 条 `workout_sets`，`setNumber` 从 1 递增、`isWarmup=false`、
///   `isCompleted=true`（补记的都是做过的）
class WorkoutLogEntry {
  final int exerciseId;
  final String exerciseName;
  final String category;

  /// 实际做了几组
  final int sets;

  /// 每组次数（力量 / 徒手动作）
  final int? reps;

  /// 每组时长秒（拉伸 / 有氧动作）
  final int? durationSec;

  /// 每组重量（kg）；null / 0 = 自重
  final double? weightKg;

  const WorkoutLogEntry({
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.sets,
    this.reps,
    this.durationSec,
    this.weightKg,
  });

  /// 从模板动作带出默认值：**组数/次数/时长沿用模板，重量留空**
  ///
  /// 重量留空是刻意的：模板里根本没有重量字段（模板是"练什么"，不是"多重"），
  /// 而"帮用户填好重量"会让补记变成假数据。
  factory WorkoutLogEntry.fromTemplateItem(WorkoutTemplateItemEntity item) {
    return WorkoutLogEntry(
      exerciseId: item.exerciseId,
      exerciseName: item.exerciseName,
      category: item.category,
      sets: item.targetSets <= 0 ? 1 : item.targetSets,
      reps: item.targetDurationSec == null ? (item.targetReps ?? 10) : null,
      durationSec: item.targetDurationSec,
      weightKg: null,
    );
  }

  /// 手动加动作时的默认值：取动作库的默认次数/时长，组数 3
  factory WorkoutLogEntry.fromExercise({
    required int exerciseId,
    required String exerciseName,
    required String category,
    int? defaultReps,
    int? defaultDurationSec,
  }) {
    final isTimed = defaultDurationSec != null && defaultDurationSec > 0;
    return WorkoutLogEntry(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      category: category,
      sets: 3,
      reps: isTimed ? null : (defaultReps ?? 10),
      durationSec: isTimed ? defaultDurationSec : null,
      weightKg: null,
    );
  }

  /// 计时动作（拉伸 / 有氧）：编辑器显示"秒"，否则显示"次"
  bool get isTimed => durationSec != null;

  WorkoutLogEntry copyWith({
    int? sets,
    int? reps,
    int? durationSec,
    double? weightKg,
    bool clearWeight = false,
  }) {
    return WorkoutLogEntry(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      category: category,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      durationSec: durationSec ?? this.durationSec,
      weightKg: clearWeight ? null : (weightKg ?? this.weightKg),
    );
  }

  /// 一行 → N 条待落库的 set（setNumber 1..N）
  ///
  /// 组数至少 1：0 组等于"没做"，那就该删掉这一行而不是存一条空记录。
  List<NewSetData> toSets() {
    final count = sets <= 0 ? 1 : sets;
    return [
      for (var i = 1; i <= count; i++)
        NewSetData(
          exerciseId: exerciseId,
          setNumber: i,
          reps: reps,
          weightKg: (weightKg ?? 0) > 0 ? weightKg : null,
          durationSec: durationSec,
          isWarmup: false,
        ),
    ];
  }
}

/// 一次补记的完整草稿
class WorkoutLogDraft {
  /// 落库的 `workouts.type`：`log` = 事后补记（不是跟着计划练的，也没有计时）。
  ///
  /// 为什么单独给一个 type（而不是拿 note 当暗号）：
  /// ① `type` 就是"这条训练是怎么来的"，补记与开练确实是两种来源；
  /// ② note 是用户写备注的地方，被系统占掉之后用户就没地方写"今天膝盖有点疼"；
  /// ③ 判定从"字符串暗号"变成"明确的来源字段"，改文案不会让标记失效。
  ///
  /// ⚠️ `log` 是**内部值**，任何 UI 都不许直接显示它 —— 用户向一律是「补记」
  /// （`WorkoutLogDraft.typeLabel`）。统计口径不受影响：统计读 getAll，不按 type 过滤。
  static const workoutType = 'log';

  /// 用户向的类型名（卡片徽标 / 详情页标签都读它）
  static const typeLabel = '补记';

  final List<WorkoutLogEntry> entries;

  const WorkoutLogDraft({this.entries = const []});

  factory WorkoutLogDraft.fromTemplate(WorkoutTemplateEntity template) {
    return WorkoutLogDraft(
      entries: template.items
          .map(WorkoutLogEntry.fromTemplateItem)
          .toList(growable: false),
    );
  }

  bool get isEmpty => entries.isEmpty;

  /// 至少一个动作才能保存（空记录没有任何信息量）
  bool get canSave => entries.isNotEmpty;

  /// 全部动作的组数合计（保存前给用户看"共 N 组"）
  int get totalSets =>
      entries.fold(0, (sum, e) => sum + (e.sets <= 0 ? 1 : e.sets));

  WorkoutLogDraft add(WorkoutLogEntry entry) =>
      WorkoutLogDraft(entries: [...entries, entry]);

  WorkoutLogDraft removeAt(int index) {
    if (index < 0 || index >= entries.length) return this;
    final next = [...entries]..removeAt(index);
    return WorkoutLogDraft(entries: next);
  }

  WorkoutLogDraft replaceAt(int index, WorkoutLogEntry entry) {
    if (index < 0 || index >= entries.length) return this;
    final next = [...entries]..[index] = entry;
    return WorkoutLogDraft(entries: next);
  }

  /// 同一动作不许加两次（会出现两条同名卡片，用户分不清该改哪条）
  bool contains(int exerciseId) =>
      entries.any((e) => e.exerciseId == exerciseId);

  /// 草稿 → 待落库的 set 列表（顺序即界面顺序，便于核对）
  List<NewSetData> toSets() =>
      [for (final entry in entries) ...entry.toSets()];
}
