import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_loss.dart';
import 'package:fittrack/core/services/checkin_days.dart';

/// 全历史体重（**斤**），按 date 升序 —— 与 `BodyMetricRepository.getAll()` 同序。
///
/// 为什么在这里换算成斤：形态阈值（0/2/5 斤）是产品口径，页面不该各自 `* 2`。
/// 排序口径只允许有一处，在仓储里；这里不排序。
final bodyWeightsJinProvider = FutureProvider<List<double>>((ref) async {
  final metrics = await ref.watch(bodyMetricRepoProvider).getAll();
  return metrics.map((m) => m.weightKg * 2).toList();
});

/// 累计打卡天数（中间断了不清零）——形象形态的唯一依据
///
/// 数据源复用 `dashboardDataProvider` 已经查好的 `allMetrics` + `allWorkouts`
/// （某天有体重或训练记录即算打卡，与"连续打卡"同一口径），不再多查一次库。
/// 它经由 dashboard → todayKeyProvider 间接跟随「今天」，跨天回前台会自动重算。
final checkinDaysProvider = Provider<AsyncValue<int>>((ref) {
  return ref.watch(dashboardDataProvider).whenData((d) {
    final dates = <DateTime>[
      for (final m in d.allMetrics) m.date,
      for (final w in d.allWorkouts) w.date,
    ];
    return countCheckinDays(dates);
  });
});

/// 减重快照（展示口径：文案与数据里仍会说"累计减重 X 斤"）
final characterLossProvider = Provider<LossSnapshot>((ref) {
  final weights =
      ref.watch(bodyWeightsJinProvider).valueOrNull ?? const <double>[];
  return CharacterLoss.of(weights);
});

/// 已声明的资产清单（只在进程内读一次）。
///
/// 为什么用它判断"素材在不在"，而不是逐张 `Image.asset` 试解码：
/// ① 只读 `AssetManifest.bin`，不解码图片（7 张图全解码一遍要几十毫秒 + 几十 MB 峰值）；
/// ② 判断发生在**渲染之前**，所以能"换图"而不是"先画白框再改"。
final characterAssetManifestProvider = FutureProvider<Set<String>>((ref) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return manifest.listAssets().toSet();
});

/// 当前角色的**完整渲染描述** —— 全 App 唯一渲染口径（C12）。
///
/// 依赖链：`userSettingsProvider` → 本 provider → 各页面。
/// 换角色只需 `invalidate(userSettingsProvider)`，级联重建（C5 的即时生效链）。
///
/// 未加载完成时给 `CharacterCatalog.fallback`（咕嘎 1 档）：
/// 首屏不能等 Future 完成再画角色，否则会先空一块再"跳出"角色。
final currentCharacterProvider = Provider<CharacterRenderSpec>((ref) {
  final settings = ref.watch(userSettingsProvider).valueOrNull;
  // 形态由累计打卡天数决定（减重只用于文案）；没读到时按 0 天 = 形态 1
  final days = ref.watch(checkinDaysProvider).valueOrNull ?? 0;
  final spec = CharacterCatalog.resolve(settings?.characterId, days);

  // 层 2（C15 / PRD §6.1）：当前角色的立绘不在包里 → 换成**咕嘎同一档**。
  // 清单还没读到时先按声明的渲染（首帧不等 IO；真实缺图还有层 3 兜底）。
  final assets = ref.watch(characterAssetManifestProvider).valueOrNull;
  if (assets == null || _assetsExistIn(spec, assets)) return spec;
  return CharacterCatalog.specOfForm(CharacterId.guga, spec.form, days);
});

/// 当前角色是否**已经确定**（设置读到过 —— 哪怕是 null = 从没设过）。
///
/// 首帧不能拿"还没读到"当"就是咕嘎"：那会让选了糯糯的用户先看到咕嘎、再跳变
/// （装机实测问题 1）。加载中 / 出错都返回 false ⇒ 调用方先画**空舞台**。
final characterResolvedProvider = Provider<bool>(
    (ref) => ref.watch(userSettingsProvider).hasValue);

/// 立绘是否都在包里。分层角色要求 head+body **两张都在**
/// （只有一半会画出"没头的人"，比缺图更糟）。
bool _assetsExistIn(CharacterRenderSpec spec, Set<String> assets) {
  if (spec.hasSplit) {
    return assets.contains(spec.headAsset) && assets.contains(spec.bodyAsset);
  }
  final image = spec.imageAsset;
  return image != null && assets.contains(image);
}

/// 切换角色（唯一的写入口，入参是枚举 ⇒ 脏值写不进去，C4）
class CharacterSelection {
  CharacterSelection(this._ref);

  final Ref _ref;

  /// 写库 → invalidate → 首页就地重建。无二次确认、无「重启生效」提示（C5）。
  Future<void> select(CharacterId id) async {
    await _ref.read(userSettingsRepoProvider).saveCharacterId(id);
    // 只失效设置：currentCharacterProvider 通过 watch 关系自动级联重建
    _ref.invalidate(userSettingsProvider);
  }
}

final characterSelectionProvider =
    Provider<CharacterSelection>((ref) => CharacterSelection(ref));
