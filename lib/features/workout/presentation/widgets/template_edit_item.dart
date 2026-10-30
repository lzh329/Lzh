/// 新建/编辑模板时的一行动作（页面内部状态模型）
class EditItem {
  final int exerciseId;
  final String name;

  /// 动作分类：strength / cardio / stretch（决定这一行填什么）
  final String category;

  final int sets;
  final int? reps;

  /// 该行时长（秒）：有氧按分钟填后换算成秒，静力/拉伸直接是秒
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

  /// 有氧动作：填的是「分钟」，展示也用分钟
  bool get isCardio => category == 'cardio';

  /// 计时类（有氧 / 静态拉伸）：没有"次数"，只有时长
  bool get isTimed => reps == null && durationSec != null;

  /// 行内展示：力量「3 × 12」/ 有氧「3 × 5 分钟」/ 静力「3 × 30 秒」
  ///
  /// 不能只看 `durationSec != null` —— 有氧和静力都走时长，但**单位不同**
  /// （分钟 vs 秒），用户看到「3 × 300 秒」会以为哪里算错了。
  String get detail {
    if (isCardio) return '$sets × ${((durationSec ?? 0) / 60).round()} 分钟';
    if (reps != null) return '$sets × $reps';
    return '$sets × ${durationSec ?? 0} 秒';
  }
}

/// 有氧动作：分钟 → 秒（存库统一按秒，开练页计时也按秒）
int cardioSeconds(int minutes) => minutes * 60;

/// 模板类型由**动作构成**派生，不由用户手选
///
/// 规则：只要有任何一个有氧动作 → cardio；否则（含空模板）→ strength。
/// 这样"深蹲 3×15 + 跳绳 3×5 分钟"这种混排模板会被判为有氧 ——
/// 它确实是一次以有氧为主的训练，而用户不需要理解"类型"这个概念。
String deriveTemplateType(Iterable<String> categories) =>
    categories.any((c) => c == 'cardio') ? 'cardio' : 'strength';
