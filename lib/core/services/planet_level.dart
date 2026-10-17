/// 减脂星球等级系统（阶段 1：等级由累计减重决定）
///
/// 设计原则：等级只依赖已有的体重数据，不新增数据库表；
/// 训练/记录行为作为后续阶段（建设值/能量值）扩展。
class PlanetStage {
  final int level;
  final String name;
  final double minLossJin; // 进入该等级所需的累计减重（斤）
  final String asset;

  const PlanetStage({
    required this.level,
    required this.name,
    required this.minLossJin,
    required this.asset,
  });
}

const planetStages = <PlanetStage>[
  PlanetStage(
    level: 1,
    name: '萌芽星球',
    minLossJin: 0,
    asset: 'assets/planet/planet_lv1.png',
  ),
  PlanetStage(
    level: 2,
    name: '森林星球',
    minLossJin: 2,
    asset: 'assets/planet/planet_lv2.png',
  ),
  PlanetStage(
    level: 3,
    name: '森林小屋',
    minLossJin: 5,
    asset: 'assets/planet/planet_lv3.png',
  ),
  PlanetStage(
    level: 4,
    name: '森林城堡',
    minLossJin: 10,
    asset: 'assets/planet/planet_lv4.png',
  ),
];

class PlanetStatus {
  final PlanetStage stage;
  final PlanetStage? next;

  /// 当前阶段内的完成度（0~1）
  final double progress;

  /// 距下一阶段还差多少斤（已满级为 null）
  final double? remainToNext;

  /// 累计减重（斤）
  final double totalLossJin;

  const PlanetStatus({
    required this.stage,
    required this.next,
    required this.progress,
    required this.remainToNext,
    required this.totalLossJin,
  });

  bool get isMax => next == null;
}

class PlanetLevelService {
  PlanetLevelService._();

  /// 根据累计减重计算星球状态
  static PlanetStatus resolve(double? totalLossJin) {
    final loss = (totalLossJin ?? 0).clamp(0.0, 999.0).toDouble();

    var idx = 0;
    for (var i = 0; i < planetStages.length; i++) {
      if (loss >= planetStages[i].minLossJin) idx = i;
    }

    final stage = planetStages[idx];
    final next =
        idx < planetStages.length - 1 ? planetStages[idx + 1] : null;

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

    return PlanetStatus(
      stage: stage,
      next: next,
      progress: progress,
      remainToNext: remain,
      totalLossJin: loss,
    );
  }
}
