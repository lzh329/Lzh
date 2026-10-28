import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

import 'migration_helper.dart';

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

class Workouts extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  TextColumn get type => text()(); // free, plan
  IntColumn get planId => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get durationSec => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

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

class FoodLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get foodId => integer().references(FoodLibrary, #id)();
  RealColumn get grams => real()(); // 摄入克数
  TextColumn get mealType => text()(); // breakfast / lunch / dinner / snack
}

class WaterLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime()();
  IntColumn get cups => integer()(); // 杯数（约200ml/杯）
}

// ─────────── v16: AI 教练聊天记录 ───────────

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

// ───────────────────── 数据库 ─────────────────────

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 仅用于测试：注入自定义 [QueryExecutor]（例如 `NativeDatabase.memory()`），
  /// 避免单测触碰真实用户数据库文件。
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 20; // v20: AI 教练「联网搜索」开关（ai_web_search_enabled）

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedExercises(this);
          await _seedFoodLibrary(this);
          await _seedWorkoutTemplates(this);
        },
        // ⚠️ drift 的 onUpgrade **不在事务里**（全包唯一事务在 alterTable() 内部）。
        // 因此下面每个迁移块里的建表 / 加列一律走 migration_helper.dart 的
        // createTableIfAbsent / addColumnIfAbsent：先查 sqlite_master /
        // PRAGMA table_info，已存在就跳过。这样即使上一次迁移只跑了一半
        // （DDL 成功但 user_version 未推进），下次启动重跑也能收敛，不会因为
        // "table already exists" / "duplicate column name" 启动即死。
        // 注意：这不解决原子性 —— 失败仍可能留下半迁移数据，但重跑不再崩。
        onUpgrade: (m, from, to) async {
          // Baseline migration (consolidates v2→v9 into single block)
          if (from < 10) {
            if (from < 2) await createTableIfAbsent(m, userSettings);
            if (from < 3) {
              await addColumnIfAbsent(m, userSettings, userSettings.birthDate);
              await addColumnIfAbsent(m, userSettings, userSettings.gender);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.activityLevel);
            }
            if (from < 4) {
              await createTableIfAbsent(m, foodLibrary);
              await createTableIfAbsent(m, foodLog);
              await _seedFoodLibrary(this);
            }
            if (from < 5) await createTableIfAbsent(m, waterLog);
            if (from < 6) {
              await addColumnIfAbsent(m, userSettings, userSettings.pinCode);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.lockEnabled);
            }
            if (from < 7) {
              await addColumnIfAbsent(m, userSettings, userSettings.speechRate);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.speechPitch);
              await addColumnIfAbsent(m, userSettings, userSettings.ttsVoice);
            }
            if (from < 8) {
              await addColumnIfAbsent(
                  m, userSettings, userSettings.reminderEnabled);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.reminderHour);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.reminderMinute);
            }
            if (from < 9) {
              await addColumnIfAbsent(m, exercises, exercises.defaultReps);
              await addColumnIfAbsent(m, exercises, exercises.defaultWeightKg);
              await addColumnIfAbsent(
                  m, exercises, exercises.defaultDurationSec);
              await addColumnIfAbsent(m, userSettings, userSettings.themeMode);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.defaultTrainingSec);
              await addColumnIfAbsent(
                  m, userSettings, userSettings.defaultRestSec);
            }
          }
          // v11: neck_cm + goal_category + diet targets
          if (from < 11) {
            await addColumnIfAbsent(m, bodyMetrics, bodyMetrics.neckCm);
            await addColumnIfAbsent(m, goals, goals.category);
            await addColumnIfAbsent(
                m, userSettings, userSettings.dailyCalorieTarget);
            await addColumnIfAbsent(
                m, userSettings, userSettings.proteinTargetG);
            await addColumnIfAbsent(m, userSettings, userSettings.carbsTargetG);
            await addColumnIfAbsent(m, userSettings, userSettings.fatTargetG);
          }
          // v12: 训练模板
          if (from < 12) {
            await createTableIfAbsent(m, workoutTemplates);
            await createTableIfAbsent(m, workoutTemplateExercises);
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
            await addColumnIfAbsent(m, userSettings, userSettings.restShortSec);
            await addColumnIfAbsent(m, userSettings, userSettings.restLongSec);
          }
          // v15: 自动备份开关
          if (from < 15) {
            await addColumnIfAbsent(
                m, userSettings, userSettings.autoBackupEnabled);
          }
          // v16: AI 教练 —— 聊天记录表 + API Key 设置列
          if (from < 16) {
            await createTableIfAbsent(m, aiChatMessages);
            await addColumnIfAbsent(m, userSettings, userSettings.aiApiKey);
          }
          // v17: AI 教练调教设定
          if (from < 17) {
            await addColumnIfAbsent(m, userSettings, userSettings.aiStyle);
            await addColumnIfAbsent(
                m, userSettings, userSettings.aiConstraints);
            await addColumnIfAbsent(
                m, userSettings, userSettings.aiReplyLength);
            await addColumnIfAbsent(
                m, userSettings, userSettings.aiTemperature);
          }
          // v18: 老的默认风格 guga 一次性切到豆包感（用户仍可在设置里改回）
          if (from < 18) {
            await customStatement(AiStyleMigration.sqlLegacyGugaToDoubao);
          }
          // v19: 用户自定义人设文案（只替换提示词「角色」段，不覆盖安全规则）
          if (from < 19) {
            await addColumnIfAbsent(
                m, userSettings, userSettings.aiPersonaCustom);
          }
          // v20: AI 教练「联网搜索」开关（老用户默认开，保持原有行为）
          if (from < 20) {
            await addColumnIfAbsent(
                m, userSettings, userSettings.aiWebSearchEnabled);
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
