import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';

/// 误报次数阈值：达到后 AI 不再自动调工具（降级为文字建议）。
///
/// 「达到」= `count >= kSickDayFalsePositiveLimit`（2 次不降级，第 3 次降级）。
const int kSickDayFalsePositiveLimit = 3;

/// 生病闸门：按天覆盖的**唯一策略入口**（数据层只管存取，不含策略）。
///
/// 生病当天只做三件事 —— 不打扰（`reminderPaused`）、缩组数（`setsScale`）、
/// 放宽热量（`calorieTargetOverride`）。**训练计划内容一律照常显示**：
/// 「拦」不等于「藏」，把计划藏起来会被当成数据丢失，比不拦更糟。
///
/// 覆盖按天存储，跨天自动失效，撤销也是按天删行，不残留任何生病痕迹。
class SickDayGate {
  SickDayGate(this._overrides, this._settings);

  final DailyOverrideRepository _overrides;
  final UserSettingsRepository _settings;

  /// 当天覆盖；无覆盖返回 **null**（不造默认值，让调用方回落到全局设置）。
  Future<DailyOverride?> overrideFor(DateTime date) =>
      _overrides.getByDate(date);

  /// 当天是否处于生病覆盖态。
  Future<bool> isActive(DateTime date) async =>
      (await _overrides.getByDate(date)) != null;

  /// 生效 / 更新当天覆盖：**只改传入的字段**，没传的保持原值（不用 0 / false 兜底）。
  ///
  /// `source` 只允许 `'user'`（用户手动）/ `'ai_health'`（AI 判断）；
  /// `setsScale` 必须落在 `(0.0, 1.0]`；`calorieTargetOverride` 必须 `> 0` 且
  /// 不得加严（见 [_validateCalorieOverride]）。
  ///
  /// **区间校验放在写侧，不靠调用方自觉**：写进去的这个值就是"今天生病的强度"，
  /// 一旦越界的数字落了库，读取侧（组数 / 热量 / 提醒三处）就得各自再判一次，
  /// 早晚会漏一处；一律抛 [ArgumentError] 且**不落库**。
  Future<void> apply({
    required DateTime date,
    int? calorieTargetOverride,
    double? setsScale,
    bool? reminderPaused,
    required String source,
  }) async {
    _validateSetsScale(setsScale);
    await _validateCalorieOverride(calorieTargetOverride);

    return _overrides.upsert(
      date: date,
      calorieTargetOverride: calorieTargetOverride,
      setsScale: setsScale,
      reminderPaused: reminderPaused,
      source: source,
    );
  }

  /// `setsScale` 合法区间 `(0.0, 1.0]`。
  ///
  /// - `0` 组 = 把今天的计划抹掉，跟「藏起来」是同一个坑，还会引出空列表 /
  ///   除零的边界；
  /// - `> 1` 是加量 —— 生病的语义里没有这一项；
  /// - `NaN` 一并挡掉（`!(NaN > 0.0)` 成立）。
  ///
  /// 不静默夹紧：夹紧会让写入方以为自己写成功了，而实际生效的是另一个值。
  static void _validateSetsScale(double? setsScale) {
    if (setsScale == null) return;
    if (!(setsScale > 0.0 && setsScale <= 1.0)) {
      throw ArgumentError.value(
        setsScale,
        'setsScale',
        '合法区间 (0.0, 1.0]：0 组等于把计划抹掉，> 1 是加量，都不是生病语义',
      );
    }
  }

  /// 热量目标**只放宽、不加严**（写侧拦截，与读侧 [relaxCalorieTarget] 同源）。
  ///
  /// 生病当天放宽目标是为了避免「今天超标 / 不达标」的假警报逼用户焦虑；
  /// 反向（比全局目标还小）就成了「App 劝你生病时少吃」—— 对一个减脂 App
  /// 那是饮食风险，不是保护。
  ///
  /// 全局目标为 null（用户没设目标）→ 没有可比对象，放过即可：那时 UI 本来就
  /// 显示「未设置」，也不存在假警报可言。
  Future<void> _validateCalorieOverride(int? override) async {
    if (override == null) return;
    if (override <= 0) {
      throw ArgumentError.value(
        override,
        'calorieTargetOverride',
        '必须 > 0：0 千卡的目标是饥饿目标，不是生病目标',
      );
    }
    final base = (await _settings.get())?.dailyCalorieTarget;
    if (base == null) return;
    if (override < base) {
      throw ArgumentError.value(
        override,
        'calorieTargetOverride',
        '生病当天只放宽不加严：$override 小于全局目标 $base',
      );
    }
  }

  /// 撤销当天覆盖：删掉那一行，组数 / 热量目标 / 提醒**立刻**恢复到原值。
  ///
  /// 计数规则：被撤的那条 `source == 'ai_health'` → 误报计数 +1；
  /// `source == 'user'`（用户自己开的自己关）→ **不计数**，不该让 AI 背锅。
  /// 当天本来就没有覆盖 → 什么都不做，也不计数。
  ///
  /// **计数写失败不许影响撤销**：撤销是用户的救回动作。少记一次只是「AI 晚一点
  /// 降级」，撤销失败则是「用户被困在生病态」。所以计数异常在此吞掉，绝不向上抛。
  Future<void> revoke(DateTime date) async {
    final existing = await _overrides.getByDate(date);
    await _overrides.clear(date);
    if (existing == null || existing.source != 'ai_health') return;
    try {
      await _settings.incrementAiHealthOverrideCount();
    } catch (_) {
      // 数没记上也要让用户出来。这里静默是刻意的，不是漏了处理。
    }
  }

  /// 组数缩放：**下限 1 组**。
  ///
  /// 缩成 0 组等于把今天的计划抹掉，跟「藏起来」是同一个坑，还会引出空列表 /
  /// 除零的边界 bug。`setsScale == null` 表示未设置，原样返回。
  static int scaleSets(int sets, double? setsScale) {
    if (setsScale == null) return sets;
    final scaled = (sets * setsScale).round();
    return scaled < 1 ? 1 : scaled;
  }

  /// 热量目标**只放宽、不加严**。
  ///
  /// `override == null` → 沿用 [base]；override 比 [base] 还小（加严）→ **不采纳**，
  /// 仍返回 [base]。生病时放宽是为了避免「今天超标」的假警报逼用户焦虑；
  /// 反向就变成「AI 劝你生病少吃」，对一个减脂 App 是饮食风险。
  static int relaxCalorieTarget(int base, int? override) {
    if (override == null) return base;
    return override < base ? base : override;
  }
}
