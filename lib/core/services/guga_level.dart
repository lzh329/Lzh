/// 咕嘎成长系统 —— 等级由累计减重决定（阶段 1：纯本地计算，不新增数据表）
///
/// 形象规划：肥咕嘎 → 微胖咕嘎 → 精神咕嘎 → 精瘦咕嘎
/// （后续阶段可扩展"建设值/能量值"，训练与记录行为参与成长）
class GugaStage {
  final int level;
  final String name;
  final String tagline; // 当前状态的一句话
  final double minLossJin; // 进入该等级所需的累计减重（斤）
  final String asset;

  const GugaStage({
    required this.level,
    required this.name,
    required this.tagline,
    required this.minLossJin,
    required this.asset,
  });
}

const gugaStages = <GugaStage>[
  GugaStage(
    level: 1,
    name: '肥咕嘎',
    tagline: '先动起来，比什么都重要',
    minLossJin: 0,
    asset: 'assets/guga/guga_lv1.png',
  ),
  GugaStage(
    level: 2,
    name: '微胖咕嘎',
    tagline: '已经上路了，保持节奏',
    minLossJin: 2,
    asset: 'assets/guga/guga_lv2.png',
  ),
  GugaStage(
    level: 3,
    name: '精神咕嘎',
    tagline: '状态在线，继续往前冲',
    minLossJin: 5,
    asset: 'assets/guga/guga_lv3.png',
  ),
  GugaStage(
    level: 4,
    name: '精瘦咕嘎',
    tagline: '你已经赢过了昨天的自己',
    minLossJin: 10,
    asset: 'assets/guga/guga_lv4.png',
  ),
];

class GugaStatus {
  final GugaStage stage;
  final GugaStage? next;

  /// 当前阶段内的完成度（0~1）
  final double progress;

  /// 距下一阶段还差多少斤（已满级为 null）
  final double? remainToNext;

  /// 累计减重（斤）
  final double totalLossJin;

  const GugaStatus({
    required this.stage,
    required this.next,
    required this.progress,
    required this.remainToNext,
    required this.totalLossJin,
  });

  bool get isMax => next == null;
}

class GugaLevelService {
  GugaLevelService._();

  /// 根据累计减重计算咕嘎形态
  static GugaStatus resolve(double? totalLossJin) {
    final loss = (totalLossJin ?? 0).clamp(0.0, 999.0).toDouble();

    var idx = 0;
    for (var i = 0; i < gugaStages.length; i++) {
      if (loss >= gugaStages[i].minLossJin) idx = i;
    }

    final stage = gugaStages[idx];
    final next = idx < gugaStages.length - 1 ? gugaStages[idx + 1] : null;

    double progress;
    double? remain;
    if (next == null) {
      progress = 1;
      remain = null;
    } else {
      final span = next.minLossJin - stage.minLossJin;
      progress = span <= 0
          ? 1
          : ((loss - stage.minLossJin) / span).clamp(0.0, 1.0);
      remain = (next.minLossJin - loss).clamp(0.0, 999.0).toDouble();
    }

    return GugaStatus(
      stage: stage,
      next: next,
      progress: progress,
      remainToNext: remain,
      totalLossJin: loss,
    );
  }
}
