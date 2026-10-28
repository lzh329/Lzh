import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'migration_failure_marker.dart';
import 'migration_helpers.dart';

part 'database.g.dart';

// ───────────────────── 表定义 ─────────────────────

class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get category => text()(); // bodyweight, gym, cardio, stretch
  TextColumn get muscleGroup => text().nullable()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  IntColumn get defaultReps => integer().nullable()();
  RealColumn get defaultWeightKg => real().nullable()();
  IntColumn get defaultDurationSec => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_workouts_date', columns: {#date})
class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text()(); // free, plan
  IntColumn get planId => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get durationSec => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_workout_sets_workout_id', columns: {#workoutId})
class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get workoutId =>
      integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get setNumber => integer()();
  IntColumn get reps => integer().nullable()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get durationSec => integer().nullable()();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(true))();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_body_metrics_date', columns: {#date})
class BodyMetrics extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  RealColumn get weightKg => real()();
  RealColumn get waistCm => real().nullable()();
  RealColumn get hipCm => real().nullable()();
  RealColumn get chestCm => real().nullable()();
  RealColumn get neckCm => real().nullable()();
  TextColumn get note => text().nullable()();
}

// ─────────── V1.1 表（预留，MVP 不操作） ───────────

class Plans extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get note => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_plan_days_plan_id', columns: {#planId})
class PlanDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId =>
      integer().references(Plans, #id, onDelete: KeyAction.cascade)();
  IntColumn get dayOfWeek => integer()(); // 0=周日, 6=周六
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetReps => integer().nullable()();
  RealColumn get targetWeightKg => real().nullable()();
  IntColumn get targetDurationSec => integer().nullable()();
  IntColumn get restSec => integer().withDefault(const Constant(90))();
}

// ─────────── V2 表（预留） ───────────

class Goals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()(); // weight, frequency, custom
  TextColumn get category => text().nullable()(); // 目标分类标签
  RealColumn get targetValue => real()();
  RealColumn get currentValue => real().withDefault(const Constant(0))();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_photos_date', columns: {#date})
class Photos extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get filePath => text()();
  TextColumn get note => text().nullable()();
}

class UserSettings extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get heightCm => real().nullable()();
  RealColumn get targetWeightKg => real().nullable()();
  DateTimeColumn get birthDate => dateTime().nullable()();
  TextColumn get gender => text().nullable()(); // male / female
  TextColumn get activityLevel => text()
      .nullable()(); // sedentary / light / moderate / active / very_active
  TextColumn get pinCode => text().nullable()();
  BoolColumn get lockEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get speechRate => real().nullable()();
  RealColumn get speechPitch => real().nullable()();
  TextColumn get ttsVoice => text().nullable()();
  BoolColumn get reminderEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get reminderHour => integer().nullable()();
  IntColumn get reminderMinute => integer().nullable()();
  TextColumn get themeMode => text().nullable()();
  IntColumn get defaultTrainingSec => integer().nullable()();
  IntColumn get defaultRestSec => integer().nullable()();
  // 循环模式休息时长（动作间 / 轮间）—— 用户在训练设置里改过就记住
  IntColumn get restShortSec => integer().nullable()();
  IntColumn get restLongSec => integer().nullable()();
  // 每周自动备份数据库开关（默认开）
  BoolColumn get autoBackupEnabled =>
      boolean().withDefault(const Constant(true))();
  // AI 教练：智谱开放平台 API Key（--dart-define 优先，此处兜底）
  TextColumn get aiApiKey => text().nullable()();
  // AI 教练调教设定：风格（doubao/guga/gentle/strict，空值 = doubao）、
  // 自定义约束（JSON 数组）、回复长度（short/medium/long）、自由度 temperature
  TextColumn get aiStyle => text().nullable()();
  TextColumn get aiConstraints => text().nullable()();
  TextColumn get aiReplyLength => text().nullable()();
  RealColumn get aiTemperature => real().nullable()();
  // 用户自定义人设文案（只替换 system prompt 的「角色」段；空值 = 用风格默认）
  TextColumn get aiPersonaCustom => text().nullable()();
  // AI 教练「联网搜索」开关（默认开）：关闭后不注册 web_search / fetch_url，
  // 提示词里也不出现联网规则 —— 直接掐掉搜索费用（¥5 / 1000 次成功请求）
  BoolColumn get aiWebSearchEnabled =>
      boolean().withDefault(const Constant(true))();
  // 饮食目标
  IntColumn get dailyCalorieTarget => integer().nullable()();
  RealColumn get proteinTargetG => real().nullable()();
  RealColumn get carbsTargetG => real().nullable()();
  RealColumn get fatTargetG => real().nullable()();
  // v21：生病拦截被「我没事，继续」撤销的累计次数
  // （只计数，**不记录病名/症状**；「我的 → 数据管理」仅在 > 0 时展示）
  IntColumn get aiHealthOverrideCount =>
      integer().withDefault(const Constant(0))();
}

class FoodLibrary extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  RealColumn get caloriesPer100g => real()();
  RealColumn get proteinPer100g => real().nullable()();
  RealColumn get fatPer100g => real().nullable()();
  RealColumn get carbsPer100g => real().nullable()();
  TextColumn get category =>
      text()(); // staple / meat / vegetable / fruit / snack / drink / other
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_food_log_date', columns: {#date})
class FoodLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get foodId => integer().references(FoodLibrary, #id)();
  RealColumn get grams => real()(); // 摄入克数
  TextColumn get mealType => text()(); // breakfast / lunch / dinner / snack
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_water_log_date', columns: {#date})
class WaterLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get cups => integer()(); // 杯数（约200ml/杯）
}

// ─────────── v16: AI 教练聊天记录 ───────────

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(name: 'idx_ai_chat_messages_created_at', columns: {#createdAt})
class AiChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get role => text()(); // user / assistant
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─────────── v12: 训练模板 ───────────

class WorkoutTemplates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get difficulty => text()(); // 入门 / 中阶 / 高阶
  TextColumn get focus => text()(); // 全身 / 放松 / 碎片
  IntColumn get minutes => integer().withDefault(const Constant(15))();
  TextColumn get description => text().nullable()();
  TextColumn get accentKey => text().withDefault(const Constant('green'))();
  BoolColumn get isRecommended =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// 与 v21 迁移块里的 CREATE INDEX IF NOT EXISTS 名字必须逐字一致
@TableIndex(
    name: 'idx_workout_template_exercises_template_id', columns: {#templateId})
class WorkoutTemplateExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get templateId => integer()
      .references(WorkoutTemplates, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId => integer().references(Exercises, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  IntColumn get targetReps => integer().nullable()();
  IntColumn get targetDurationSec => integer().nullable()();
}

// ─────────── v21: 按日覆盖 + 周报缓存 ───────────

/// v21：按日覆盖 —— 用户主动暂停 / 系统按健康状况降级。
///
/// **只作用于当天**：读取时按 `date == 今天 0 点` 精确匹配，无记录就回到默认
/// 行为。不允许"昨天降级了今天继续降"。
///
/// 一天最多一条：用 `uniqueKeys` 表达（SQLite 会自动建 `sqlite_autoindex_*`，
/// 按该列查已经走索引），**不要再额外建 `idx_daily_overrides_date`** ——
/// 重复索引只会拖慢写入。
class DailyOverrides extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 归属日期（本地时区当天 0 点），一天最多一条
  DateTimeColumn get date => dateTime()();

  /// 今天的热量目标（null = 沿用 UserSettings.dailyCalorieTarget）
  IntColumn get calorieTargetOverride => integer().nullable()();

  /// 组数系数（0.5~1.0，null = 不缩减）
  RealColumn get setsScale => real().nullable()();

  /// 今天不排称重/训练提醒
  BoolColumn get reminderPaused =>
      boolean().withDefault(const Constant(false))();

  /// 今天是否跳过宏量/热量缺口评判：normal / skip
  ///
  /// 这是**语义开关**而不是数值覆盖：`skip` 时 AI 不做任何主动评判与催促，
  /// 但用户主动问必须如实回答。数值下调只会把催促变得温和，本质还在催。
  TextColumn get macroJudgement =>
      text().withDefault(const Constant('normal'))();

  /// 来源：`user`（用户主动）/ `ai_health`（AI 生病闸门判定降级）。
  ///
  /// `sleep` 为**预留值，本期不写入**（还没有睡眠数据来源）。
  /// 本期只有 AI 生病闸门会写这张表。
  TextColumn get source => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {date},
      ];
}

/// v21：周报缓存（只建表，功能进 P1 —— 本迭代**不许有任何代码读写它**）。
///
/// token 必须分列存：DeepSeek 输入/输出单价不同，只存总数算不出成本。
class WeeklyReportCache extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 该周周一 0 点
  DateTimeColumn get weekStart => dateTime()();

  TextColumn get content => text()();
  TextColumn get model => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  IntColumn get totalTokens => integer().nullable()();

  /// 风格 + 长度 + 自定义人设的指纹；变化则缓存失效重生成
  TextColumn get personaFingerprint => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {weekStart},
      ];
}

// ───────────────────── 数据库 ─────────────────────

/// 当前 schema 版本（唯一事实来源）。
///
/// 单独提成常量是为了让启动期健探测（`database_health.dart` 读文件头
/// `user_version` 判断 marker 是否僵尸）与真实版本**不可能不同步** ——
/// 硬编码两份版本号迟早会漂，而漂了的后果是把健康库误判成失败库。
const int kSchemaVersion = 21;

/// v21 新增的 9 条索引（迁移侧定义）。
///
/// ⚠️ 索引必须**两处定义**，只写一处不会有任何测试变红，属于"上线三个月后
/// 才会发现"的坑：
///   ① 各表类上的 `@TableIndex(...)` → 只影响 `onCreate → createAll`，即**新装用户**；
///   ② 本常量 → 只影响**老库升级**（`if (from < 21)` 块里逐条执行）。
/// 两处的名字必须逐字一致，`IF NOT EXISTS` 才能自然去重。
/// 改一处必须同时改另一处，反之亦然。
const List<String> kV21Indexes = [
  'CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts (date)',
  'CREATE INDEX IF NOT EXISTS idx_body_metrics_date ON body_metrics (date)',
  'CREATE INDEX IF NOT EXISTS idx_food_log_date ON food_log (date)',
  'CREATE INDEX IF NOT EXISTS idx_water_log_date ON water_log (date)',
  'CREATE INDEX IF NOT EXISTS idx_photos_date ON photos (date)',
  'CREATE INDEX IF NOT EXISTS idx_ai_chat_messages_created_at '
      'ON ai_chat_messages (created_at)',
  'CREATE INDEX IF NOT EXISTS idx_workout_sets_workout_id '
      'ON workout_sets (workout_id)',
  'CREATE INDEX IF NOT EXISTS idx_plan_days_plan_id ON plan_days (plan_id)',
  'CREATE INDEX IF NOT EXISTS idx_workout_template_exercises_template_id '
      'ON workout_template_exercises (template_id)',
];

/// 从 `CREATE INDEX IF NOT EXISTS idx_xxx ON ...` 里取出索引名，用于步骤级诊断。
String _indexNameOf(String sql) {
  final match =
      RegExp(r'INDEX\s+IF\s+NOT\s+EXISTS\s+(\w+)', caseSensitive: false)
          .firstMatch(sql);
  return match?.group(1) ?? 'unknown';
}

/// 数据库迁移 SQL 常量（便于单测锁住行为）
class AiStyleMigration {
  AiStyleMigration._();

  /// v18：把老的默认风格 guga 一次性切到豆包感
  /// （guga 长期是默认值，大概率不是用户主动选择；用户仍可在「教练设定」改回）
  static const sqlLegacyGugaToDoubao =
      "UPDATE user_settings SET ai_style = 'doubao' WHERE ai_style = 'guga'";
}

@DriftDatabase(
  tables: [
    Exercises,
    Workouts,
    WorkoutSets,
    BodyMetrics,
    Plans,
    PlanDays,
    Goals,
    Photos,
    UserSettings,
    FoodLibrary,
    FoodLog,
    WaterLog,
    WorkoutTemplates,
    WorkoutTemplateExercises,
    AiChatMessages,
    DailyOverrides,
    WeeklyReportCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// 迁移失败标记的落盘目录（null = 应用文档目录）。
  /// 单测注入临时目录，避免碰平台通道。
  final Directory? markerBaseDir;

  AppDatabase({this.markerBaseDir}) : super(_openConnection());

  /// 仅用于测试：注入自定义 [QueryExecutor]（例如 `NativeDatabase.memory()`），
  /// 避免单测触碰真实用户数据库文件。
  AppDatabase.withExecutor(super.executor, {this.markerBaseDir});

  @override
  // v20: AI 教练「联网搜索」开关（ai_web_search_enabled）
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedExercises(this);
          await _seedFoodLibrary(this);
          await _seedWorkoutTemplates(this);
        },
        // ⚠️ drift 的 onUpgrade **不在事务里**（全包唯一事务在 alterTable() 内部）。
        // 因此下面每个迁移块里的建表 / 加列一律走 migration_helpers.dart 的
        // createTableIfNotExists / addColumnIfNotExists：先查 sqlite_master /
        // PRAGMA table_info，已存在就跳过。这样即使上一次迁移只跑了一半
        // （DDL 成功但 user_version 未推进），下次启动重跑也能收敛，不会因为
        // "table already exists" / "duplicate column name" 启动即死。
        // 注意：这不解决原子性 —— 失败仍可能留下半迁移数据，但重跑不再崩。
        // ⚠️ 失败时写 marker（步骤级），重跑由幂等助手收敛。
        //
        // 事务策略（已定稿）：**v21 及之前全部不包事务**。v21 是纯 DDL，
        // 失败现场只是"多两张空表 / 少几条索引"，用户数据一个字节都没动；
        // 而裸 BEGIN 与 drift 执行器混用是新增风险。靠幂等收敛兜住更稳。
        // 含数据变换（backfill / 删列 / 改类型）的迁移才必须整段包事务，
        // 见 DEVELOPMENT_PLAYBOOK.md 第七章。
        onUpgrade: (m, from, to) async {
          // 当前执行到哪一步（步骤级，不是表级）：v21 有 9 条 CREATE INDEX，
          // 只记表名等于没记 —— 用户截图回来我们定位不到是哪一条。
          var step = 'start';
          try {
            // Baseline migration (consolidates v2→v9 into single block)
            if (from < 10) {
              if (from < 2) await createTableIfNotExists(m, userSettings);
              if (from < 3) {
                await addColumnIfNotExists(
                    m, userSettings, userSettings.birthDate);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.gender);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.activityLevel);
              }
              if (from < 4) {
                await createTableIfNotExists(m, foodLibrary);
                await createTableIfNotExists(m, foodLog);
                await _seedFoodLibrary(this);
              }
              if (from < 5) await createTableIfNotExists(m, waterLog);
              if (from < 6) {
                await addColumnIfNotExists(
                    m, userSettings, userSettings.pinCode);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.lockEnabled);
              }
              if (from < 7) {
                await addColumnIfNotExists(
                    m, userSettings, userSettings.speechRate);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.speechPitch);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.ttsVoice);
              }
              if (from < 8) {
                await addColumnIfNotExists(
                    m, userSettings, userSettings.reminderEnabled);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.reminderHour);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.reminderMinute);
              }
              if (from < 9) {
                await addColumnIfNotExists(m, exercises, exercises.defaultReps);
                await addColumnIfNotExists(
                    m, exercises, exercises.defaultWeightKg);
                await addColumnIfNotExists(
                    m, exercises, exercises.defaultDurationSec);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.themeMode);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.defaultTrainingSec);
                await addColumnIfNotExists(
                    m, userSettings, userSettings.defaultRestSec);
              }
            }
            // v11: neck_cm + goal_category + diet targets
            if (from < 11) {
              await addColumnIfNotExists(m, bodyMetrics, bodyMetrics.neckCm);
              await addColumnIfNotExists(m, goals, goals.category);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.dailyCalorieTarget);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.proteinTargetG);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.carbsTargetG);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.fatTargetG);
            }
            // v12: 训练模板
            if (from < 12) {
              await createTableIfNotExists(m, workoutTemplates);
              await createTableIfNotExists(m, workoutTemplateExercises);
              await _seedWorkoutTemplates(this);
            }
            // v13: 平板支撑等静力动作默认计时（已有数据补默认时长）
            if (from < 13) {
              await customStatement(
                'UPDATE exercises SET default_duration_sec = 30 '
                "WHERE name = '平板支撑' AND default_duration_sec IS NULL",
              );
            }
            // v14: 循环模式休息时长持久化（动作间 / 轮间）
            if (from < 14) {
              await addColumnIfNotExists(
                  m, userSettings, userSettings.restShortSec);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.restLongSec);
            }
            // v15: 自动备份开关
            if (from < 15) {
              await addColumnIfNotExists(
                  m, userSettings, userSettings.autoBackupEnabled);
            }
            // v16: AI 教练 —— 聊天记录表 + API Key 设置列
            if (from < 16) {
              await createTableIfNotExists(m, aiChatMessages);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiApiKey);
            }
            // v17: AI 教练调教设定
            if (from < 17) {
              await addColumnIfNotExists(m, userSettings, userSettings.aiStyle);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiConstraints);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiReplyLength);
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiTemperature);
            }
            // v18: 老的默认风格 guga 一次性切到豆包感（用户仍可在设置里改回）
            if (from < 18) {
              await customStatement(AiStyleMigration.sqlLegacyGugaToDoubao);
            }
            // v19: 用户自定义人设文案（只替换提示词「角色」段，不覆盖安全规则）
            if (from < 19) {
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiPersonaCustom);
            }
            // v20: AI 教练「联网搜索」开关（老用户默认开，保持原有行为）
            if (from < 20) {
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiWebSearchEnabled);
            }
            // v21: 按日覆盖 + 周报缓存 + 生病撤销计数 + 9 条索引
            if (from < 21) {
              step = 'createTable:daily_overrides';
              await createTableIfNotExists(m, dailyOverrides);
              step = 'createTable:weekly_report_cache';
              await createTableIfNotExists(m, weeklyReportCache);
              step = 'addColumn:ai_health_override_count';
              await addColumnIfNotExists(
                  m, userSettings, userSettings.aiHealthOverrideCount);
              for (final sql in kV21Indexes) {
                step = 'index:${_indexNameOf(sql)}';
                await customStatement(sql);
              }
            }

            // 成功：清掉可能存在的旧失败标记（清不掉不影响正确性）
            await MigrationFailureMarker.clear(baseDir: markerBaseDir);
          } catch (e) {
            // 迁移失败不是崩溃，是"可以重试的状态"：先留下可诊断的痕迹再上抛。
            // 写 marker 自身失败绝不能盖掉原始异常。
            try {
              await MigrationFailureMarker.record(
                fromVersion: from,
                targetVersion: to,
                failingStep: step,
                baseDir: markerBaseDir,
              );
            } catch (_) {
              // 忽略：原始异常更重要
            }
            rethrow;
          }
        },
      );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'fittrack.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// 内置动作种子数据
Future<void> _seedExercises(AppDatabase db) async {
  final exercises = [
    // 徒手
    ('俯卧撑', 'bodyweight', '胸部'),
    ('钻石俯卧撑', 'bodyweight', '肱三头肌'),
    ('宽距俯卧撑', 'bodyweight', '胸部'),
    ('平板支撑', 'bodyweight', '核心'),
    ('仰卧起坐', 'bodyweight', '腹部'),
    ('卷腹', 'bodyweight', '腹部'),
    ('深蹲', 'bodyweight', '腿部'),
    ('弓步蹲', 'bodyweight', '腿部'),
    ('臀桥', 'bodyweight', '臀部'),
    ('引体向上', 'bodyweight', '背部'),
    ('悬垂举腿', 'bodyweight', '腹部'),
    // 器械
    ('杠铃深蹲', 'gym', '腿部'),
    ('杠铃卧推', 'gym', '胸部'),
    ('杠铃硬拉', 'gym', '背部'),
    ('杠铃划船', 'gym', '背部'),
    ('杠铃推举', 'gym', '肩部'),
    ('哑铃弯举', 'gym', '肱二头肌'),
    ('哑铃侧平举', 'gym', '肩部'),
    ('哑铃飞鸟', 'gym', '胸部'),
    ('腿举', 'gym', '腿部'),
    ('腿弯举', 'gym', '腿部'),
    ('坐姿划船', 'gym', '背部'),
    ('高位下拉', 'gym', '背部'),
    // 有氧
    ('跑步', 'cardio', '全身'),
    ('跳绳', 'cardio', '全身'),
    ('骑自行车', 'cardio', '腿部'),
    ('游泳', 'cardio', '全身'),
    ('椭圆机', 'cardio', '全身'),
    ('划船机', 'cardio', '全身'),
    // 拉伸
    ('腿部拉伸', 'stretch', '腿部'),
    ('肩背拉伸', 'stretch', '肩部'),
    ('全身拉伸', 'stretch', '全身'),
  ];

  for (final e in exercises) {
    await db.into(db.exercises).insert(ExercisesCompanion.insert(
          name: e.$1,
          category: e.$2,
          muscleGroup: Value(e.$3),
          isCustom: const Value(false),
        ));
  }

  // 静力动作默认计时（平板支撑 30 秒），供模板编辑识别为"时长"类型
  await db.customStatement(
    'UPDATE exercises SET default_duration_sec = 30 '
    "WHERE name = '平板支撑' AND default_duration_sec IS NULL",
  );
}

/// 内置食物库种子数据（每100g热量kcal）
Future<void> _seedFoodLibrary(AppDatabase db) async {
  // 幂等：v4 迁移块重跑时表已建好，种子已灌过就不再重复插入
  final existing = await db.select(db.foodLibrary).get();
  if (existing.isNotEmpty) return;

  final foods = [
    // 主食
    ('白米饭', 116, 2.6, 0.3, 25.9, 'staple'),
    ('馒头', 223, 7.0, 1.1, 44.2, 'staple'),
    ('面条(煮)', 110, 3.4, 0.3, 22.0, 'staple'),
    ('全麦面包', 246, 10.0, 3.4, 41.3, 'staple'),
    ('红薯', 86, 1.6, 0.1, 20.1, 'staple'),
    ('玉米', 112, 4.0, 1.2, 22.8, 'staple'),
    ('燕麦片', 377, 13.5, 6.7, 61.6, 'staple'),
    // 肉类
    ('鸡胸肉', 133, 31.0, 1.2, 0.0, 'meat'),
    ('鸡腿肉', 181, 20.0, 11.0, 0.0, 'meat'),
    ('猪瘦肉', 143, 20.3, 6.2, 1.5, 'meat'),
    ('牛肉(瘦)', 125, 20.2, 4.2, 0.2, 'meat'),
    ('鸡蛋', 144, 13.3, 8.8, 2.8, 'meat'),
    ('虾仁', 93, 20.0, 0.8, 0.0, 'meat'),
    ('三文鱼', 208, 20.4, 13.4, 0.0, 'meat'),
    // 蔬菜
    ('西兰花', 36, 4.1, 0.6, 4.3, 'vegetable'),
    ('番茄', 19, 0.9, 0.2, 3.5, 'vegetable'),
    ('黄瓜', 16, 0.8, 0.2, 2.9, 'vegetable'),
    ('菠菜', 28, 3.1, 0.4, 3.6, 'vegetable'),
    ('生菜', 16, 1.4, 0.2, 2.1, 'vegetable'),
    ('胡萝卜', 39, 1.0, 0.2, 8.8, 'vegetable'),
    // 水果
    ('苹果', 53, 0.2, 0.2, 13.5, 'fruit'),
    ('香蕉', 93, 1.4, 0.2, 22.0, 'fruit'),
    ('橙子', 48, 0.8, 0.2, 11.0, 'fruit'),
    ('西瓜', 31, 0.6, 0.1, 7.0, 'fruit'),
    // 零食/饮品
    ('牛奶(全脂)', 65, 3.0, 3.6, 4.9, 'drink'),
    ('豆浆', 31, 2.4, 1.3, 1.6, 'drink'),
    ('酸奶(原味)', 72, 3.5, 3.1, 8.4, 'drink'),
    ('坚果(杏仁)', 579, 21.2, 49.9, 21.6, 'snack'),
    ('黑巧克力', 546, 4.9, 31.3, 59.4, 'snack'),
  ];

  for (final f in foods) {
    await db.into(db.foodLibrary).insert(FoodLibraryCompanion.insert(
          name: f.$1,
          caloriesPer100g: f.$2.toDouble(),
          proteinPer100g: Value(f.$3),
          fatPer100g: Value(f.$4),
          carbsPer100g: Value(f.$5),
          category: f.$6,
        ));
  }
}

// ───────────────────── 训练模板种子 ─────────────────────

class _TemplateItemSeed {
  final String exerciseName;
  final int sets;
  final int? reps;
  final int? durationSec;

  const _TemplateItemSeed(
    this.exerciseName,
    this.sets, {
    this.reps,
    this.durationSec,
  });
}

class _TemplateSeed {
  final String name;
  final String difficulty;
  final String focus;
  final int minutes;
  final String accent;
  final String description;
  final List<_TemplateItemSeed> items;

  const _TemplateSeed({
    required this.name,
    required this.difficulty,
    required this.focus,
    required this.minutes,
    required this.accent,
    required this.description,
    required this.items,
  });
}

const _templateSeeds = [
  _TemplateSeed(
    name: '新手减脂',
    difficulty: '入门',
    focus: '全身',
    minutes: 15,
    accent: 'green',
    description: '低强度全身训练，适合刚开始减脂的用户',
    items: [
      _TemplateItemSeed('深蹲', 3, reps: 15),
      _TemplateItemSeed('俯卧撑', 3, reps: 10),
      _TemplateItemSeed('平板支撑', 3, durationSec: 30),
      _TemplateItemSeed('卷腹', 3, reps: 12),
    ],
  ),
  _TemplateSeed(
    name: '燃脂训练',
    difficulty: '中阶',
    focus: '全身',
    minutes: 20,
    accent: 'orange',
    description: '中等强度全身燃脂，高效消耗热量',
    items: [
      _TemplateItemSeed('深蹲', 4, reps: 15),
      _TemplateItemSeed('弓步蹲', 3, reps: 12),
      _TemplateItemSeed('俯卧撑', 3, reps: 12),
      _TemplateItemSeed('仰卧起坐', 4, reps: 15),
    ],
  ),
  _TemplateSeed(
    name: '高效HIIT',
    difficulty: '高阶',
    focus: '全身',
    minutes: 15,
    accent: 'red',
    description: '高强度间歇训练，快速燃烧',
    items: [
      _TemplateItemSeed('深蹲', 4, reps: 20),
      _TemplateItemSeed('俯卧撑', 3, reps: 15),
      _TemplateItemSeed('跳绳', 3, durationSec: 60),
      _TemplateItemSeed('卷腹', 3, reps: 20),
    ],
  ),
  _TemplateSeed(
    name: '办公室运动',
    difficulty: '入门',
    focus: '碎片',
    minutes: 10,
    accent: 'cyan',
    description: '无需器械，10 分钟碎片化训练',
    items: [
      _TemplateItemSeed('深蹲', 2, reps: 15),
      _TemplateItemSeed('俯卧撑', 2, reps: 10),
      _TemplateItemSeed('平板支撑', 2, durationSec: 30),
      _TemplateItemSeed('肩背拉伸', 2, durationSec: 60),
    ],
  ),
  _TemplateSeed(
    name: '睡前拉伸',
    difficulty: '入门',
    focus: '放松',
    minutes: 10,
    accent: 'purple',
    description: '放松全身肌肉，改善睡眠质量',
    items: [
      _TemplateItemSeed('全身拉伸', 2, durationSec: 60),
      _TemplateItemSeed('腿部拉伸', 3, durationSec: 60),
      _TemplateItemSeed('肩背拉伸', 2, durationSec: 60),
    ],
  ),
];

/// 写入推荐训练模板（动作按名称匹配动作库）
Future<void> _seedWorkoutTemplates(AppDatabase db) async {
  // 幂等：v12 迁移块重跑时表已建好，模板已灌过就不再重复插入
  final existingTemplates = await db.select(db.workoutTemplates).get();
  if (existingTemplates.isNotEmpty) return;

  final exercises = await db.select(db.exercises).get();
  final idByName = {for (final e in exercises) e.name: e.id};

  for (final t in _templateSeeds) {
    final templateId = await db.into(db.workoutTemplates).insert(
          WorkoutTemplatesCompanion.insert(
            name: t.name,
            difficulty: t.difficulty,
            focus: t.focus,
            minutes: Value(t.minutes),
            description: Value(t.description),
            accentKey: Value(t.accent),
            isRecommended: const Value(true),
          ),
        );
    var order = 0;
    for (final item in t.items) {
      final exerciseId = idByName[item.exerciseName];
      if (exerciseId == null) continue;
      await db.into(db.workoutTemplateExercises).insert(
            WorkoutTemplateExercisesCompanion.insert(
              templateId: templateId,
              exerciseId: exerciseId,
              sortOrder: Value(order++),
              targetSets: Value(item.sets),
              targetReps: Value(item.reps),
              targetDurationSec: Value(item.durationSec),
            ),
          );
    }
  }
}
