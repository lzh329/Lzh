import 'dart:convert';

/// 动作芯片的**唯一白名单**（与 PRD C1 逐字一致）。
///
/// 白名单外的 key 一律不渲染：芯片是"这条建议现在就能做"，点了没反应
/// 是最难查的一类 bug，所以宁可少一个按钮。
const Set<String> kCoachChipKeys = <String>{
  'open_workout',
  'log_weight',
  'log_food',
  'set_reminder',
  'open_trends',
};

/// 一条可点的动作芯片。
///
/// **只存 key，不存 route / payload**：
/// 「去开练」的落点取决于**点击那一刻**的活跃计划（有 → 执行页，无 → 快速开始）。
/// 把 route 存进消息 JSON，用户删掉计划之后点那个芯片就是白屏 —— 这个坑本仓库
/// 已经踩过（`app_router.dart` 里那些 redirect 就是为它留的）。
/// label 由常量表给：改文案不必迁移任何数据。
class CoachChip {
  final String key;

  const CoachChip(this.key);

  String get label => labels[key] ?? '';

  bool get isKnown => kCoachChipKeys.contains(key);

  static const Map<String, String> labels = <String, String>{
    'open_workout': '去开练',
    'log_weight': '记体重',
    'log_food': '记饮食',
    'set_reminder': '设提醒',
    'open_trends': '看趋势',
  };

  /// 落库格式：`[{"k":"log_weight"}]`。null / '' / 非法 JSON / 白名单外 key
  /// 一律丢弃（C1 与老数据兼容一次解决：老行的 `chips IS NULL` → 空列表）。
  static List<CoachChip> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <CoachChip>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <CoachChip>[];
      final out = <CoachChip>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final key = item['k'];
        if (key is! String || !kCoachChipKeys.contains(key)) continue;
        if (out.any((c) => c.key == key)) continue;
        out.add(CoachChip(key));
      }
      return out;
    } catch (_) {
      return const <CoachChip>[];
    }
  }

  /// 空列表 → null（**不写 `'[]'`**）：null 与空数组是同一个意思，写两套口径
  /// 会让"多少条消息带芯片"这类统计算错。
  static String? encode(List<CoachChip> chips) {
    final known = chips.where((c) => c.isKnown).toList();
    if (known.isEmpty) return null;
    return jsonEncode([for (final c in known) {'k': c.key}]);
  }
}
