import 'package:fittrack/features/ai/domain/coach_chip.dart';

/// 芯片生成的 6 条规则（**纯函数、零 IO**，C2 要求每条可单独证伪）。
///
/// 为什么不用模型生成：每轮多一次调用 = 成本翻倍 + 多 3 秒延迟，换来的是
/// "按钮文案更聪明"，收益与代价完全不成比例；而且模型给的 key 一不留神就是
/// 白名单外的，点了没反应是最难查的 bug。
///
/// 为什么"今日有无记录"是入参而不是在这里查库：那部分是 IO，抽到
/// `CoachChipService` 之后这里的 6 条规则可以不做任何 mock 直接单测。
class CoachChipRules {
  CoachChipRules._();

  static const int maxChips = 3;

  /// 判定顺序即优先级，命中即收集，同一 key 不重复，取前 3 个。
  ///
  /// [toolReceipts] 的格式是 **`工具名:回执JSON`**（例：
  /// `start_workout:{"ok":false,"error":"没找到模板「燃脂」"}`）。
  ///
  /// 为什么要带工具名：`AiToolContext.failureReceipt()` 只产出
  /// `{"ok":false,"error":"..."}`，**不含工具名** —— 光看回执分不清是
  /// `start_workout` 失败还是 `log_food` 失败。把名字拼在回执前面是本模块
  /// 与工具上下文之间的显式约定，改这里必须同步改
  /// `AiChatNotifier._toolReceipts()`。
  static List<CoachChip> build({
    required String assistantText,
    required List<String> toolReceipts,
    required bool hasWeightToday,
    required bool hasFoodToday,
  }) {
    final out = <CoachChip>[];
    void add(String key) {
      if (out.length >= maxChips) return;
      if (out.any((c) => c.key == key)) return;
      if (!kCoachChipKeys.contains(key)) return;
      out.add(CoachChip(key));
    }

    // ① 本轮 start_workout 回执 ok:false → 去开练
    final startFailed = toolReceipts.any((r) =>
        r.startsWith('start_workout:') && r.contains('"ok":false'));
    if (startFailed) add('open_workout');

    // ② 正文含开练 / 开始训练 / 模板
    if (_has(assistantText, const ['开练', '开始训练', '模板'])) add('open_workout');

    // ③ 体重 / 称重 / 上秤 —— 且**今日无体重记录**（C5）
    if (_has(assistantText, const ['体重', '称重', '上秤']) && !hasWeightToday) {
      add('log_weight');
    }

    // ④ 吃 / 热量 / 蛋白 / 碳水 / 饮食 —— 且今日无饮食记录（C5）
    if (_has(assistantText, const ['吃', '热量', '蛋白', '碳水', '饮食']) &&
        !hasFoodToday) {
      add('log_food');
    }

    // ⑤ 提醒 / 几点 / 早点睡 / 作息
    if (_has(assistantText, const ['提醒', '几点', '早点睡', '作息'])) {
      add('set_reminder');
    }

    // ⑥ 趋势 / 进度 / 变化 / 这周 / 上周
    if (_has(assistantText, const ['趋势', '进度', '变化', '这周', '上周'])) {
      add('open_trends');
    }

    // 一条都不命中 → 空列表。**不给兜底芯片**：一旦有一半时候给的是无关按钮，
    // 用户就学会无视它，那时它连装饰都算不上，只是噪音。
    return out;
  }

  static bool _has(String text, List<String> keywords) {
    if (text.isEmpty) return false;
    return keywords.any(text.contains);
  }
}
