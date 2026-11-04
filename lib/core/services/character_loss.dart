/// 减重口径的纯计算 —— 形态用「历史最大减重」，趋势页用「当前累计减重」。
///
/// 为什么两个口径不是一个：形态一旦按实时值算，一顿火锅（水钠潴留 ±1~2 斤）就会
/// 让用户的形象退档 —— 那不是"数据在波动"，那是 App 在说他胖了（决策 4）。
///
/// "只升不降"不是"存一个永不下降的值"，而是"口径换成历史最低点"：
/// 零新增字段、零新增一致性风险，删记录后还能自愈（C7）。
library;

/// 一次快照：起点 / 最低点 / 当前值，以及由此派生的两个减重数字。
class LossSnapshot {
  /// 起始体重（按 date 升序的第一条）；0 条记录时为 null
  final double? startJin;

  /// 全历史最低体重；0 条记录时为 null
  final double? minJin;

  /// 最新一条体重；0 条记录时为 null
  final double? currentJin;

  /// **形态口径** = start − min（clamp ≥ 0）。只升不降由它保证。
  final double historyMaxLossJin;

  /// **展示口径** = start − current（可为负：涨了）
  final double currentLossJin;

  const LossSnapshot({
    required this.startJin,
    required this.minJin,
    required this.currentJin,
    required this.historyMaxLossJin,
    required this.currentLossJin,
  });
}

abstract final class CharacterLoss {
  /// 从按 `date` **升序**的体重列表（斤）算快照。
  ///
  /// 入参必须升序，本函数**不排序**：排序口径只允许有一处（放在仓储里）。
  /// 0 条 / 1 条记录都是合法输入 —— 返回两个 loss = 0，调用方按 form 1 渲染，
  /// 不会出现「再减 NaN 斤」（边界表 8.x）。
  static LossSnapshot of(List<double> weightsJinAsc) {
    if (weightsJinAsc.isEmpty) {
      return const LossSnapshot(
        startJin: null,
        minJin: null,
        currentJin: null,
        historyMaxLossJin: 0,
        currentLossJin: 0,
      );
    }

    // 过滤 NaN/Infinity：外部数据损坏时宁可少一个点，也不要让整个首页崩掉
    final values = weightsJinAsc.where((w) => w.isFinite).toList();
    if (values.isEmpty) {
      return const LossSnapshot(
        startJin: null,
        minJin: null,
        currentJin: null,
        historyMaxLossJin: 0,
        currentLossJin: 0,
      );
    }

    final start = values.first;
    var min = values.first;
    for (final v in values) {
      if (v < min) min = v;
    }
    final current = values.last;

    return LossSnapshot(
      startJin: start,
      minJin: min,
      currentJin: current,
      // clamp 到 0：体重涨了就是"还没减"，不是负数（更不是"胖了 X 斤"）
      historyMaxLossJin: (start - min) < 0 ? 0 : (start - min),
      currentLossJin: start - current,
    );
  }
}
