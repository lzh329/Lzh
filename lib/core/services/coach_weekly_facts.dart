import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

/// 本周一 00:00（本地时区）—— **全 App 唯一的周口径**。
///
/// 用 `DateTime.weekday` 做日期算术，绝不用"第几周编号"：ISO 周编号在跨年
/// （12 月底那一周属于下一年）与时区上都会错，而日期不会漂。
DateTime mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// 周消息的去重键：`weekly:{本周一 yyyy-MM-dd}`
///
/// 键里放**投递周**的周一，不放被总结的那一周 —— 否则每周的键都会等于
/// "上周的键"，第二周就再也不会生成。正文内容仍然是"上周的总结"，两者不冲突。
String weeklyDedupeKey(DateTime weekStart) =>
    'weekly:${weekStart.year.toString().padLeft(4, '0')}-'
    '${weekStart.month.toString().padLeft(2, '0')}-'
    '${weekStart.day.toString().padLeft(2, '0')}';

/// 周消息正文所需要的 7 个数字（**DTO，不拼文案**）。
///
/// 空值语义是这里最要紧的一条（PRD 共享知识 2）：
/// `null = 不知道 / 算不出来`，`0 = 真的是 0`。任何地方都不许 `?? 0`
/// 把"不知道"变成"0" —— 那会产出「体重变化 0.0 斤」这种假精确。
class WeeklyFacts {
  /// 投递周的周一 00:00（去重键与推送时刻都按它算）
  final DateTime weekStart;

  /// 上一周（`weekStart - 7d`）的训练次数。0 是真实值，模板第 3 条用它。
  final int workoutCount;

  /// 上一周训练总时长（分钟）。0 同样是真实值。
  final int workoutMinutes;

  /// 上一周首条体重（斤）；上周称重不足 2 次时为 null
  final double? weightStartJin;

  /// 上一周末条体重（斤）；同上
  final double? weightEndJin;

  /// 上一周称重天数（按自然日去重）
  final int weighInDays;

  /// 当前累计减重（全期，需 ≥2 条记录）
  final double? totalLossJin;

  /// 当前距目标剩余（斤，需有目标体重）
  final double? remainingJin;

  /// 昵称（trim 后为空视为未设置）
  final String? nickname;

  const WeeklyFacts({
    required this.weekStart,
    required this.workoutCount,
    required this.workoutMinutes,
    required this.weighInDays,
    this.weightStartJin,
    this.weightEndJin,
    this.totalLossJin,
    this.remainingJin,
    this.nickname,
  });

  /// 上一周数据的起止（用于 AI prompt 里给人看）
  DateTime get dataStart => weekStart.subtract(const Duration(days: 7));
  DateTime get dataEnd => weekStart.subtract(const Duration(days: 1));

  /// 只有首尾两条都有值，才谈得上"体重变化"
  bool get weightChangeKnown => weightStartJin != null && weightEndJin != null;

  double? get weightChangeJin =>
      weightChangeKnown ? weightEndJin! - weightStartJin! : null;
}

/// 取数：把 5 张表里的记录压成 [WeeklyFacts]。
///
/// 只读、不写、不含策略 —— 这样"跨周只统计上周"可以用内存库直接证伪（W-1）。
class WeeklyFactLoader {
  WeeklyFactLoader({
    required WorkoutRepository workout,
    required BodyMetricRepository body,
    required UserSettingsRepository settings,
  })  : _workout = workout,
        _body = body,
        _settings = settings;

  final WorkoutRepository _workout;
  final BodyMetricRepository _body;
  final UserSettingsRepository _settings;

  /// [now] 默认当前时刻（单测可传固定值）
  Future<WeeklyFacts> load({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final weekStart = mondayOf(today);
    final dataStart = weekStart.subtract(const Duration(days: 7));
    final dataEnd = weekStart.subtract(const Duration(days: 1));

    final workouts = await _workout.getAll(from: dataStart, to: dataEnd);
    final minutes = workouts.fold<int>(
      0,
      (sum, w) => sum + ((w.durationSec ?? 0) ~/ 60),
    );

    // 上周体重：仓储的排序不参与计算，这里自己按日期升序排一次
    final weekMetrics = [...await _body.getAll(from: dataStart, to: dataEnd)]
      ..sort((a, b) => a.date.compareTo(b.date));
    final weighInDays = weekMetrics
        .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
        .toSet()
        .length;
    // 只有 ≥2 次称重才谈得上"从 A 走到 B"；1 次算不出变化 → 整段不提体重
    final hasWeightChange = weekMetrics.length >= 2;

    final allMetrics = [...await _body.getAll()]
      ..sort((a, b) => a.date.compareTo(b.date));

    final settings = await _settings.get();
    final latestJin =
        allMetrics.isEmpty ? null : allMetrics.last.weightKg * 2;
    final firstJin = allMetrics.isEmpty ? null : allMetrics.first.weightKg * 2;
    final totalLossJin =
        (firstJin != null && latestJin != null && allMetrics.length >= 2)
            ? firstJin - latestJin
            : null;
    final targetJin = settings?.targetWeightKg == null
        ? null
        : settings!.targetWeightKg! * 2;
    final remainingJin =
        (latestJin != null && targetJin != null) ? latestJin - targetJin : null;

    final nickname = settings?.nickname?.trim();

    return WeeklyFacts(
      weekStart: weekStart,
      workoutCount: workouts.length,
      workoutMinutes: minutes,
      weighInDays: weighInDays,
      weightStartJin: hasWeightChange ? weekMetrics.first.weightKg * 2 : null,
      weightEndJin: hasWeightChange ? weekMetrics.last.weightKg * 2 : null,
      totalLossJin: totalLossJin,
      remainingJin: remainingJin,
      nickname: (nickname == null || nickname.isEmpty) ? null : nickname,
    );
  }
}
