import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart'
    show AppDatabase, DailyOverridesCompanion;
// 生成的数据行类也叫 DailyOverride（drift 按表名去复数），加前缀以免和下面的实体同名。
import 'package:fittrack/core/database/database.dart' as row show DailyOverride;

/// `source` 的合法取值 —— 只有这两个。`sleep` 只是预留，本期没有写入方。
const Set<String> kDailyOverrideSources = <String>{'user', 'ai_health'};

/// `macroJudgement` 默认值：照常评判。
const String kMacroJudgementNormal = 'normal';

/// 某一天的覆盖（v21）：只作用于当天，一天最多一条。
///
/// **null = 未设置，0 / false = 真的设成了 0 / false** —— 二者不可互换，任何
/// 地方都不许 `?? 0` / `?? false` 兜底。
class DailyOverride {
  const DailyOverride({
    required this.date,
    this.calorieTargetOverride,
    this.setsScale,
    this.reminderPaused = false,
    this.macroJudgement = kMacroJudgementNormal,
    required this.source,
    required this.createdAt,
  });

  final DateTime date;

  /// 当天热量目标；null = 未设置（沿用 UserSettings.dailyCalorieTarget）
  final int? calorieTargetOverride;

  /// 组数系数；null = 未设置（不缩减）
  final double? setsScale;

  final bool reminderPaused;

  /// 当天是否跳过宏量评判：normal / skip
  final String macroJudgement;
  final String source;
  final DateTime createdAt;
}

/// `daily_overrides` 的数据层：只做存取，不含任何策略。放 core/database 是因为
/// 它横跨饮食 / 训练 / 提醒三个域，不属于任何单一 feature；"生病了该降多少"
/// 是下一棒的事。
class DailyOverrideRepository {
  DailyOverrideRepository(this._db);

  final AppDatabase _db;

  /// 规整到当天 0 点 —— 和 getDailyNutrition 同一口径，避免"同一天存了两条不同时刻的记录"。
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 没传（null）= `Value.absent()`（保留原值），传了 = 精确写入。
  static Value<T> _orAbsent<T extends Object>(T? v) =>
      v == null ? const Value.absent() : Value<T>(v);

  /// 当天没有覆盖就返回 null —— 不造默认值，让调用方自己回落到全局设置。
  Future<DailyOverride?> getByDate(DateTime date) async {
    final r = await (_db.select(_db.dailyOverrides)
          ..where((t) => t.date.equals(_dayOf(date))))
        .getSingleOrNull();
    return r == null ? null : _toEntity(r);
  }

  /// 写 / 改当天的覆盖：一天一行，第二次写是覆盖不是新增。
  ///
  /// **只改传进来的字段**：没传的保持原值（用 `Value.absent()` 表达），绝不用
  /// 0 / false 兜底冲掉已有值。
  Future<void> upsert({
    required DateTime date,
    int? calorieTargetOverride,
    double? setsScale,
    bool? reminderPaused,
    String? macroJudgement,
    required String source,
  }) async {
    if (!kDailyOverrideSources.contains(source)) {
      throw ArgumentError.value(source, 'source', '只允许 user / ai_health');
    }

    // 没传（null）= absent → 保留原值；传了 = 精确写入（包括真的写 null）
    final calorie = _orAbsent(calorieTargetOverride);
    final scale = _orAbsent(setsScale);
    final paused = _orAbsent(reminderPaused);
    final judgement = _orAbsent(macroJudgement);

    final day = _dayOf(date);
    await _db.transaction(() async {
      final existing = await (_db.select(_db.dailyOverrides)
            ..where((t) => t.date.equals(day)))
          .getSingleOrNull();

      if (existing == null) {
        await _db.into(_db.dailyOverrides).insert(
              DailyOverridesCompanion.insert(
                date: day,
                calorieTargetOverride: calorie,
                setsScale: scale,
                reminderPaused: paused,
                macroJudgement: judgement,
                source: source,
                createdAt: Value(DateTime.now()),
              ),
            );
        return;
      }

      // 已存在：source 必传必改，其余字段传了才改，createdAt 不动。
      await (_db.update(_db.dailyOverrides)..where((t) => t.date.equals(day)))
          .write(DailyOverridesCompanion(
        source: Value(source),
        calorieTargetOverride: calorie,
        setsScale: scale,
        reminderPaused: paused,
        macroJudgement: judgement,
      ));
    });
  }

  /// 撤销：删掉当天那条，让当天回到"没有覆盖"的状态。
  Future<void> clear(DateTime date) async {
    await (_db.delete(_db.dailyOverrides)
          ..where((t) => t.date.equals(_dayOf(date))))
        .go();
  }

  Future<List<DailyOverride>> listRange(DateTime from, DateTime to) async {
    final start = _dayOf(from);
    final end = _dayOf(to).add(const Duration(days: 1));
    final rows = await (_db.select(_db.dailyOverrides)
          ..where((t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm(expression: t.date)]))
        .get();
    return rows.map(_toEntity).toList();
  }

  DailyOverride _toEntity(row.DailyOverride r) => DailyOverride(
        date: r.date,
        calorieTargetOverride: r.calorieTargetOverride,
        setsScale: r.setsScale,
        reminderPaused: r.reminderPaused,
        macroJudgement: r.macroJudgement,
        source: r.source,
        createdAt: r.createdAt,
      );
}
