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

/// 有氧模板的总时长上下限（分钟）
const int kCardioMinMinutes = 5;
const int kCardioMaxMinutes = 180;

/// 有氧总时长校验：越界返回提示文案，合法返回 null
///
/// 刻意**不静默截断**：用户输入 300 时把它改成 180 再保存，等于偷偷改了
/// 他的意图；正确做法是拒绝保存并让他看见原因。
String? cardioMinutesError(int minutes) {
  if (minutes < kCardioMinMinutes) return '至少 $kCardioMinMinutes 分钟';
  if (minutes > kCardioMaxMinutes) return '最多 $kCardioMaxMinutes 分钟';
  return null;
}

/// 有氧模板里每个动作的存储形态：只填时长（分钟）
///
/// 统一映射成 `sets=1 / durationSec=分钟×60 / reps=null` ——
/// 图表的"组"概念对有氧没有意义，但库里 targetSets 非空，固定 1 最省事；
/// 时长按秒存（与开练页的计时代码一致），避免两处单位不同。
({int sets, int? reps, int durationSec}) cardioItemValues(int minutes) => (
      sets: 1,
      reps: null,
      durationSec: minutes * 60,
    );
