import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

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
  IntColumn get workoutId => integer().references(Workouts, #id, onDelete: KeyAction.cascade)();
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
  IntColumn get planId => integer().references(Plans, #id, onDelete: KeyAction.cascade)();
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
  TextColumn get activityLevel => text().nullable()(); // sedentary / light / moderate / active / very_active
  TextColumn get pinCode => text().nullable()();
  BoolColumn get lockEnabled => boolean().withDefault(const Constant(false))();
  RealColumn get speechRate => real().nullable()();
  RealColumn get speechPitch => real().nullable()();
  TextColumn get ttsVoice => text().nullable()();
  BoolColumn get reminderEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get reminderHour => integer().nullable()();
  IntColumn get reminderMinute => integer().nullable()();
  TextColumn get themeMode => text().nullable()();
  IntColumn get defaultTrainingSec => integer().nullable()();
  IntColumn get defaultRestSec => integer().nullable()();
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
  TextColumn get category => text()(); // staple / meat / vegetable / fruit / snack / drink / other
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

// ───────────────────── 数据库 ─────────────────────

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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 11; // v11: neck_cm + goal_category + diet targets

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedExercises(this);
      await _seedFoodLibrary(this);
    },
    onUpgrade: (m, from, to) async {
      // Baseline migration (consolidates v2→v9 into single block)
      if (from < 10) {
        if (from < 2) await m.createTable(userSettings);
        if (from < 3) {
          await m.addColumn(userSettings, userSettings.birthDate);
          await m.addColumn(userSettings, userSettings.gender);
          await m.addColumn(userSettings, userSettings.activityLevel);
        }
        if (from < 4) {
          await m.createTable(foodLibrary);
          await m.createTable(foodLog);
          await _seedFoodLibrary(this);
        }
        if (from < 5) await m.createTable(waterLog);
        if (from < 6) {
          await m.addColumn(userSettings, userSettings.pinCode);
          await m.addColumn(userSettings, userSettings.lockEnabled);
        }
        if (from < 7) {
          await m.addColumn(userSettings, userSettings.speechRate);
          await m.addColumn(userSettings, userSettings.speechPitch);
          await m.addColumn(userSettings, userSettings.ttsVoice);
        }
        if (from < 8) {
          await m.addColumn(userSettings, userSettings.reminderEnabled);
          await m.addColumn(userSettings, userSettings.reminderHour);
          await m.addColumn(userSettings, userSettings.reminderMinute);
        }
        if (from < 9) {
          await m.addColumn(exercises, exercises.defaultReps);
          await m.addColumn(exercises, exercises.defaultWeightKg);
          await m.addColumn(exercises, exercises.defaultDurationSec);
          await m.addColumn(userSettings, userSettings.themeMode);
          await m.addColumn(userSettings, userSettings.defaultTrainingSec);
          await m.addColumn(userSettings, userSettings.defaultRestSec);
        }
      }
      // v11: neck_cm + goal_category + diet targets
      if (from < 11) {
        await m.addColumn(bodyMetrics, bodyMetrics.neckCm);
        await m.addColumn(goals, goals.category);
        await m.addColumn(userSettings, userSettings.dailyCalorieTarget);
        await m.addColumn(userSettings, userSettings.proteinTargetG);
        await m.addColumn(userSettings, userSettings.carbsTargetG);
        await m.addColumn(userSettings, userSettings.fatTargetG);
      }
      // v12+ migrations go here
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
}

/// 内置食物库种子数据（每100g热量kcal）
Future<void> _seedFoodLibrary(AppDatabase db) async {
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
