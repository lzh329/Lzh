import 'package:fittrack/features/ai/domain/ai_tool_exception.dart';
import 'package:fittrack/features/ai/domain/ai_tool_inputs.dart';

/// 参数解析与校验（纯函数，便于单测）
class AiToolArgs {
  AiToolArgs._();

  // ───────────── 基础解析 ─────────────

  /// 数字（num 或数字字符串），解析失败返回 null
  static double? numOf(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// 严格整数（接受 30、"30"、30.0），解析失败返回 null
  ///
  /// 带小数的入参（如 3.7）直接抛异常，不静默截断 —— 用于 goal_id 这类 id 校验。
  static int? intOf(Object? v) {
    if (v is int) return v;
    final d = numOf(v);
    if (d == null) return null;
    if (d != d.roundToDouble()) throw const AiToolException('需要整数');
    return d.toInt();
  }

  /// 宽松整数（保留旧行为：小数静默截断），用于杯数 / 分钟这类容错数值参数
  static double? lenientDoubleOf(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static int? lenientIntOf(Object? v) {
    if (v is int) return v;
    final d = numOf(v);
    if (d == null) return null;
    return d.toInt();
  }

  /// 布尔（接受 true/false、"true"/"false"、1/0、"是"/"否" 等），解析失败返回 null
  static bool? boolOf(Object? v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (const ['true', '1', 'yes', 'on', '开', '开启', '是'].contains(s)) {
        return true;
      }
      if (const ['false', '0', 'no', 'off', '关', '关闭', '否'].contains(s)) {
        return false;
      }
    }
    return null;
  }

  /// 可选数值 + 范围校验（缺失返回 null，越界抛异常）
  static double? _optionalRange(
    Map<String, dynamic> args,
    String key,
    String label, {
    required double min,
    required double max,
  }) {
    final raw = args[key];
    if (raw == null || (raw is String && raw.trim().isEmpty)) return null;
    final v = numOf(raw);
    if (v == null) throw AiToolException('$label格式不正确');
    if (v < min || v > max) {
      throw AiToolException('$label不合理（应在 ${_range(min)}~${_range(max)} 之间）');
    }
    return v;
  }

  static String _range(double v) {
    final rounded = v.roundToDouble();
    return v == rounded ? rounded.round().toString() : v.toStringAsFixed(1);
  }

  // ───────────── 已有工具 ─────────────

  /// 体重（斤）→ 公斤，校验 40~600 斤
  static double weightKg(Map<String, dynamic> args) {
    final v = args['weight_jin'];
    final jin = numOf(v);
    if (jin == null) throw const AiToolException('缺少体重数值');
    if (jin < 40 || jin > 600) {
      throw const AiToolException('体重数值不合理（应在 40~600 斤）');
    }
    return jin / 2;
  }

  static double weightJin(Map<String, dynamic> args) => weightKg(args) * 2;

  /// 可选体重（斤）：缺失返回 null，给了就同样校验 40~600
  static double? optionalWeightKg(Map<String, dynamic> args) {
    final jin = _optionalRange(args, 'weight_jin', '体重数值', min: 40, max: 600);
    return jin == null ? null : jin / 2;
  }

  /// 目标体重（斤）→ 公斤，校验 40~600 斤（set_target_weight 用 target_jin 字段）
  static double targetWeightKg(Map<String, dynamic> args) {
    final jin = numOf(args['target_jin']);
    if (jin == null) throw const AiToolException('缺少目标体重数值');
    if (jin < 40 || jin > 600) {
      throw const AiToolException('目标体重数值不合理（应在 40~600 斤）');
    }
    return jin / 2;
  }

  /// 杯数，校验 1~30
  static int cups(Map<String, dynamic> args) {
    final cups = lenientIntOf(args['cups']);
    if (cups == null) throw const AiToolException('缺少杯数');
    if (cups < 1 || cups > 30) {
      throw const AiToolException('杯数不合理（应在 1~30 杯）');
    }
    return cups;
  }

  /// 日期：默认今天；禁止未来、禁止超过一年前
  static DateTime date(Map<String, dynamic> args, {String key = 'date'}) {
    final raw = args[key];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (raw == null || (raw is String && raw.trim().isEmpty)) return today;
    final parsed = DateTime.tryParse('$raw');
    if (parsed == null) throw const AiToolException('日期格式不正确（需要 YYYY-MM-DD）');
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    if (d.isAfter(today)) throw const AiToolException('不能记录未来日期');
    if (today.difference(d).inDays > 365) {
      throw const AiToolException('日期太早（超过一年前）');
    }
    return d;
  }

  /// 统计范围，默认 week
  static String range(Map<String, dynamic> args) {
    final v = args['range'];
    final r = v is String ? v : 'week';
    return const ['week', 'month', 'all'].contains(r) ? r : 'week';
  }

  /// 食物名称（非空、长度合理）
  static String foodName(Map<String, dynamic> args) {
    final v = args['food_name'];
    final name = v is String ? v.trim() : '';
    if (name.isEmpty) throw const AiToolException('缺少食物名称');
    if (name.length > 30) throw const AiToolException('食物名称太长');
    return name;
  }

  /// 重量（克），1~2000
  static double grams(Map<String, dynamic> args) {
    final grams = numOf(args['grams']);
    if (grams == null) throw const AiToolException('缺少重量');
    if (grams < 1 || grams > 2000) {
      throw const AiToolException('重量不合理（应在 1~2000 克）');
    }
    return grams;
  }

  /// 每 100 克热量，0~900
  static double caloriesPer100g(Map<String, dynamic> args) {
    final c = numOf(args['calories_per_100g']);
    if (c == null) throw const AiToolException('缺少热量估算');
    if (c < 0 || c > 900) {
      throw const AiToolException('热量数值不合理（应在 0~900 千卡/100g）');
    }
    return c;
  }

  /// 每 100 克三大营养素（**可选**）：缺省返回 null，绝不返回 0
  ///
  /// 0 只在这个数真的是 0 时才出现（比如植物油的碳水）。缺就留空，
  /// 让 UI 显示「—」；拿 0 兜底会被当成"算过了、结果是 0 克"。
  static double? optionalProteinPer100g(Map<String, dynamic> args) =>
      _optionalRange(args, 'protein_per_100g', '蛋白', min: 0, max: 100);

  static double? optionalFatPer100g(Map<String, dynamic> args) =>
      _optionalRange(args, 'fat_per_100g', '脂肪', min: 0, max: 100);

  static double? optionalCarbsPer100g(Map<String, dynamic> args) =>
      _optionalRange(args, 'carbs_per_100g', '碳水', min: 0, max: 100);

  /// 餐次：非法或缺失时按当前时间推断
  static String mealType(Map<String, dynamic> args) {
    final raw = args['meal_type'];
    if (raw is String &&
        const ['breakfast', 'lunch', 'dinner', 'snack'].contains(raw)) {
      return raw;
    }
    final hour = DateTime.now().hour;
    if (hour < 10) return 'breakfast';
    if (hour < 15) return 'lunch';
    if (hour < 20) return 'dinner';
    return 'snack';
  }

  static const mealLabels = {
    'breakfast': '早餐',
    'lunch': '午餐',
    'dinner': '晚餐',
    'snack': '加餐',
  };

  /// 训练类型：兼容中英文，未知归为"其他"
  static String workoutType(Map<String, dynamic> args) {
    final raw = args['workout_type'];
    final v = raw is String ? raw.trim() : '';
    if (const ['力量', '有氧', '拉伸', '其他'].contains(v)) return v;
    const map = {
      'strength': '力量',
      'cardio': '有氧',
      'stretch': '拉伸',
      'stretching': '拉伸',
      'other': '其他',
    };
    return map[v.toLowerCase()] ?? '其他';
  }

  /// 训练时长（分钟），1~300
  static int minutes(Map<String, dynamic> args) {
    final m = lenientIntOf(args['minutes']);
    if (m == null) throw const AiToolException('缺少训练时长');
    if (m < 1 || m > 300) {
      throw const AiToolException('训练时长不合理（应在 1~300 分钟）');
    }
    return m;
  }

  /// 训练备注（可选，截断保护）
  static String? workoutNote(Map<String, dynamic> args) {
    final v = args['note'];
    if (v is! String) return null;
    final note = v.trim();
    if (note.isEmpty) return null;
    return note.length > 120 ? note.substring(0, 120) : note;
  }

  /// 日期展示：今天 / 昨天 / 10-24
  static String dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${d.month}-${d.day}';
  }

  // ───────────── log_measurements ─────────────

  /// 围度三项：各字段 30~200cm，至少提供一项
  static AiMeasurements measurements(Map<String, dynamic> args) {
    final m = AiMeasurements(
      waistCm: _optionalRange(args, 'waist_cm', '腰围', min: 30, max: 200),
      hipCm: _optionalRange(args, 'hip_cm', '臀围', min: 30, max: 200),
      chestCm: _optionalRange(args, 'chest_cm', '胸围', min: 30, max: 200),
    );
    if (m.isEmpty) {
      throw const AiToolException('至少要给一个围度（腰围 / 臀围 / 胸围）');
    }
    return m;
  }

  // ───────────── update_profile ─────────────

  /// 身体信息：身高 100~250cm，性别 male/female，出生年 1920~（今年-10）；至少一项
  static AiProfileInput profile(Map<String, dynamic> args) {
    final heightCm =
        _optionalRange(args, 'height_cm', '身高', min: 100, max: 250);

    final rawGender = args['gender'];
    String? gender;
    if (rawGender is String && rawGender.trim().isNotEmpty) {
      final g = rawGender.trim().toLowerCase();
      if (!const ['male', 'female'].contains(g)) {
        throw const AiToolException('性别只能是 male 或 female');
      }
      gender = g;
    }

    final rawYear = args['birth_year'];
    int? birthYear;
    if (rawYear != null && !(rawYear is String && rawYear.trim().isEmpty)) {
      birthYear = lenientIntOf(rawYear);
      if (birthYear == null) throw const AiToolException('出生年份格式不正确');
      final maxYear = DateTime.now().year - 10;
      if (birthYear < 1920 || birthYear > maxYear) {
        throw AiToolException('出生年份不合理（应在 1920~$maxYear 之间）');
      }
    }

    // 目标体重：单位是**斤**（与用户口语一致），内部转公斤存库
    double? targetWeightKg;
    final rawTarget = args['target_weight_jin'];
    if (rawTarget != null &&
        !(rawTarget is String && rawTarget.trim().isEmpty)) {
      final jin = lenientDoubleOf(rawTarget);
      if (jin == null || jin < 50 || jin > 500) {
        throw const AiToolException('目标体重不合理（应在 50~500 斤之间）');
      }
      targetWeightKg = jin / 2;
    }

    // 活动水平
    String? activityLevel;
    final rawActivity = args['activity_level'];
    if (rawActivity is String && rawActivity.trim().isNotEmpty) {
      final level = rawActivity.trim().toLowerCase();
      if (!const [
        'sedentary',
        'light',
        'moderate',
        'active',
        'very_active',
      ].contains(level)) {
        throw const AiToolException(
            'activity_level 必须是 sedentary / light / moderate / active / very_active 之一');
      }
      activityLevel = level;
    }

    final input = AiProfileInput(
      heightCm: heightCm,
      gender: gender,
      birthYear: birthYear,
      targetWeightKg: targetWeightKg,
      activityLevel: activityLevel,
    );
    if (input.isEmpty) {
      throw const AiToolException('至少要给一项身体信息（身高 / 性别 / 出生年份）');
    }
    return input;
  }

  // ───────────── set_diet_target ─────────────

  /// 饮食目标：热量 800~5000 千卡，三大宏量 0~500g；至少一项
  static AiDietTargetInput dietTarget(Map<String, dynamic> args) {
    final calories =
        _optionalRange(args, 'calories', '每日热量目标', min: 800, max: 5000);
    final input = AiDietTargetInput(
      calories: calories?.round(),
      proteinG: _optionalRange(args, 'protein_g', '蛋白目标', min: 0, max: 500),
      carbsG: _optionalRange(args, 'carbs_g', '碳水目标', min: 0, max: 500),
      fatG: _optionalRange(args, 'fat_g', '脂肪目标', min: 0, max: 500),
    );
    if (input.isEmpty) {
      throw const AiToolException('至少要给一项饮食目标（热量 / 蛋白 / 碳水 / 脂肪）');
    }
    return input;
  }

  // ───────────── set_reminder ─────────────

  /// 可选数值（缺省 null，**不兜 0** —— 0 代表"真的给了 0"）
  static double? optionalDouble(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null || (v is String && v.trim().isEmpty)) return null;
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(v.toString().trim());
    if (parsed == null) throw AiToolException('$key 格式不正确');
    return parsed;
  }

  // ───────────── 身体记录（body_metrics） ─────────────

  /// 可选记录 id
  static int? optionalMeasurementId(Map<String, dynamic> args) =>
      lenientIntOf(args['id']);

  /// 可选日期（yyyy-MM-dd）
  static DateTime? optionalMeasurementDate(Map<String, dynamic> args) {
    final raw = args['date'];
    if (raw is! String || raw.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) throw const AiToolException('日期格式应为 yyyy-MM-dd');
    return parsed;
  }

  /// 部位：waist / hip / chest / weight
  static String measurementPart(Map<String, dynamic> args) {
    final raw = args['part'];
    final part = raw is String ? raw.trim().toLowerCase() : '';
    if (!const ['waist', 'hip', 'chest', 'weight'].contains(part)) {
      throw const AiToolException(
          'part 必须是 waist（腰围）/ hip（臀围）/ chest（胸围）/ weight（体重）之一');
    }
    return part;
  }

  /// 必填布尔（开关类参数）：缺失或无法解析直接抛异常
  static bool boolArg(Map<String, dynamic> args, String key, String label) {
    final b = boolOf(args[key]);
    if (b == null) throw AiToolException('缺少$label设置（需要 true 或 false）');
    return b;
  }

  /// 小时 0~23，缺失返回 null
  static int? optionalHour(Map<String, dynamic> args) {
    final h = _optionalRange(args, 'hour', '小时', min: 0, max: 23);
    return h?.round();
  }

  /// 分钟 0~59，缺失返回 null
  static int? optionalMinute(Map<String, dynamic> args) {
    final m = _optionalRange(args, 'minute', '分钟', min: 0, max: 59);
    return m?.round();
  }

  // ───────────── delete_records ─────────────

  /// 要删除的记录类型：weight / food / workout / water
  /// delete_template 的模板 id（必填，缺失/非法抛异常）
  static int templateId(Map<String, dynamic> args) {
    final id = lenientIntOf(args['id']);
    if (id == null || id <= 0) throw const AiToolException('缺少模板 id');
    return id;
  }

  static String recordType(Map<String, dynamic> args) {
    final raw = args['type'];
    final type = raw is String ? raw.trim().toLowerCase() : '';
    if (!AiRecordTypes.all.contains(type)) {
      throw const AiToolException(
          '不支持的记录类型（只能是 weight / food / workout / water）');
    }
    return type;
  }

  // ───────────── manage_goal ─────────────

  /// 目标操作：create / complete / delete
  static String goalAction(Map<String, dynamic> args) {
    final raw = args['action'];
    final action = raw is String ? raw.trim().toLowerCase() : '';
    if (!AiGoalActions.all.contains(action)) {
      throw const AiToolException('不支持的目标操作（只能是 create / complete / delete）');
    }
    return action;
  }

  /// 目标 id（complete / delete 必填），需为正整数
  static int goalId(Map<String, dynamic> args) {
    final id = intOf(args['goal_id']);
    if (id == null) throw const AiToolException('缺少目标 id');
    if (id <= 0) throw const AiToolException('目标 id 不合理');
    return id;
  }

  /// 目标类型（create 必填）：weight / frequency / custom
  static String goalType(Map<String, dynamic> args) {
    final raw = args['type'];
    final type = raw is String ? raw.trim().toLowerCase() : '';
    if (!const ['weight', 'frequency', 'custom'].contains(type)) {
      throw const AiToolException('目标类型只能是 weight / frequency / custom');
    }
    return type;
  }

  /// 目标数值（create 必填）：需大于 0
  static double goalTargetValue(Map<String, dynamic> args) {
    final v = numOf(args['target_value']);
    if (v == null) throw const AiToolException('缺少目标数值');
    if (v <= 0) throw const AiToolException('目标数值要大于 0');
    if (v > 100000) throw const AiToolException('目标数值不合理');
    return v;
  }

  /// 目标分类标签（可选，截断保护）
  static String? goalCategory(Map<String, dynamic> args) {
    final raw = args['category'];
    if (raw is! String) return null;
    final c = raw.trim();
    if (c.isEmpty) return null;
    return c.length > 20 ? c.substring(0, 20) : c;
  }

  /// 目标结束日期（可选）：允许未来，但不超过 5 年后
  static DateTime? goalEndDate(Map<String, dynamic> args) {
    final raw = args['end_date'];
    if (raw == null || (raw is String && raw.trim().isEmpty)) return null;
    final parsed = DateTime.tryParse('$raw');
    if (parsed == null) throw const AiToolException('日期格式不正确（需要 YYYY-MM-DD）');
    final d = DateTime(parsed.year, parsed.month, parsed.day);
    final limit = DateTime.now().add(const Duration(days: 365 * 5));
    if (d.isAfter(limit)) throw const AiToolException('结束日期太远（超过 5 年）');
    return d;
  }

  // ───────────── search_food ─────────────

  /// 搜索关键词：非空、≤20 字
  static String searchQuery(Map<String, dynamic> args) {
    final raw = args['query'];
    final q = raw is String ? raw.trim() : '';
    if (q.isEmpty) throw const AiToolException('缺少搜索关键词');
    if (q.length > 20) throw const AiToolException('搜索关键词太长（20 字以内）');
    return q;
  }

  // ───────────── query_exercises ─────────────

  /// 动作搜索关键词（可选）：空 / 缺失返回 null，表示不按名称筛选
  static String? optionalExerciseQuery(Map<String, dynamic> args) {
    final raw = args['query'];
    if (raw is! String) return null;
    final q = raw.trim();
    if (q.isEmpty) return null;
    if (q.length > 20) {
      throw const AiToolException('搜索关键词太长（20 字以内）');
    }
    return q;
  }

  /// 动作分类（可选）：缺失返回 null，非法值抛异常
  static String? optionalExerciseCategory(Map<String, dynamic> args) {
    final raw = args['category'];
    if (raw is! String || raw.trim().isEmpty) return null;
    final category = AiExerciseCategories.normalize(raw);
    if (category == null) {
      throw AiToolException('不支持的分类"${raw.trim()}"（只能是 徒手 / 器械 / 有氧 / 拉伸）');
    }
    return category;
  }

  /// 动作分类（必填）：中文 / 英文均可，统一归一化成 bodyweight 等英文值
  static String exerciseCategory(Map<String, dynamic> args) {
    final raw = args['category'];
    if (raw is! String || raw.trim().isEmpty) {
      throw const AiToolException('缺少动作分类（只能是 徒手 / 器械 / 有氧 / 拉伸）');
    }
    return optionalExerciseCategory(args)!;
  }

  /// 动作名称：1~30 字
  static String exerciseName(Map<String, dynamic> args) {
    final raw = args['name'];
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) throw const AiToolException('缺少动作名称');
    if (name.length > 30) throw const AiToolException('动作名称太长（30 字以内）');
    return name;
  }

  /// 目标肌群（可选）：≤10 字，超长截断
  static String? optionalMuscleGroup(Map<String, dynamic> args) {
    final raw = args['muscle_group'];
    if (raw is! String) return null;
    final group = raw.trim();
    if (group.isEmpty) return null;
    return group.length > 10 ? group.substring(0, 10) : group;
  }

  /// 默认次数（可选）：1~100
  static int? optionalDefaultReps(Map<String, dynamic> args) {
    final v = _optionalRange(args, 'default_reps', '默认次数', min: 1, max: 100);
    return v?.round();
  }

  /// 默认时长（可选，秒）：5~600
  static int? optionalDefaultDurationSec(Map<String, dynamic> args) {
    final v =
        _optionalRange(args, 'default_duration_sec', '默认时长', min: 5, max: 600);
    return v?.round();
  }

  // ───────────── create_exercise ─────────────

  /// create_exercise 的完整入参
  static AiExerciseInput exercise(Map<String, dynamic> args) {
    final input = AiExerciseInput(
      name: exerciseName(args),
      category: exerciseCategory(args),
      muscleGroup: optionalMuscleGroup(args),
      defaultReps: optionalDefaultReps(args),
      defaultDurationSec: optionalDefaultDurationSec(args),
    );
    return input;
  }

  // ───────────── create_template ─────────────

  /// 模板名称：1~30 字
  static String templateName(Map<String, dynamic> args) {
    final raw = args['name'];
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) throw const AiToolException('缺少模板名称');
    if (name.length > 30) throw const AiToolException('模板名称太长（30 字以内）');
    return name;
  }

  /// 模板难度：入门 / 中阶 / 高阶，兼容 beginner / intermediate / advanced
  static String templateDifficulty(Map<String, dynamic> args) {
    final raw = args['difficulty'];
    final v = raw is String ? raw.trim() : '';
    if (v.isEmpty) {
      throw const AiToolException('缺少模板难度（只能是 入门 / 中阶 / 高阶）');
    }
    final d = AiTemplateCommand.difficultyOf(v);
    if (d == null) {
      throw AiToolException('不支持的难度"$v"（只能是 入门 / 中阶 / 高阶）');
    }
    return d;
  }

  /// 模板侧重：全身 / 放松 / 碎片，兼容 full_body / relax / fragment
  static String templateFocus(Map<String, dynamic> args) {
    final raw = args['focus'];
    final v = raw is String ? raw.trim() : '';
    if (v.isEmpty) {
      throw const AiToolException('缺少模板侧重（只能是 全身 / 放松 / 碎片）');
    }
    final f = AiTemplateCommand.focusOf(v);
    if (f == null) {
      throw AiToolException('不支持的侧重"$v"（只能是 全身 / 放松 / 碎片）');
    }
    return f;
  }

  /// 模板时长（分钟）：5~180
  static int templateMinutes(Map<String, dynamic> args) {
    final m = lenientIntOf(args['minutes']);
    if (m == null) throw const AiToolException('缺少模板时长');
    if (m < 5 || m > 180) {
      throw const AiToolException('模板时长不合理（应在 5~180 分钟）');
    }
    return m;
  }

  /// 模板说明（可选）：≤100 字，超长截断
  static String? optionalTemplateDescription(Map<String, dynamic> args) {
    final raw = args['description'];
    if (raw is! String) return null;
    final d = raw.trim();
    if (d.isEmpty) return null;
    return d.length > 100 ? d.substring(0, 100) : d;
  }

  /// 模板动作列表：1~12 项
  static List<AiTemplateItemInput> templateItems(Map<String, dynamic> args) {
    final raw = args['items'];
    if (raw is! List || raw.isEmpty) {
      throw const AiToolException('模板至少要包含 1 个动作');
    }
    if (raw.length > 12) throw const AiToolException('模板最多 12 个动作');
    final items = <AiTemplateItemInput>[];
    for (final entry in raw) {
      if (entry is! Map) throw const AiToolException('模板动作格式不正确');
      items.add(templateItem(Map<String, dynamic>.from(entry)));
    }
    return items;
  }

  /// 单个模板动作：sets 缺省 3；reps / duration_sec 都不给时默认 reps=10
  ///
  /// `category` / `muscle_group` 只在这个动作需要**新建**时用到：
  /// - category 可省略（省略即兜底），给了非法值直接抛错（不猜用户的意图）
  /// - muscle_group 超长自动截断到 10 字
  static AiTemplateItemInput templateItem(Map<String, dynamic> args) {
    final rawName = args['exercise_name'];
    final name = rawName is String ? rawName.trim() : '';
    if (name.isEmpty) throw const AiToolException('模板里有动作缺少名称');
    if (name.length > 30) throw const AiToolException('动作名称太长（30 字以内）');

    final sets = _optionalRange(args, 'sets', '组数', min: 1, max: 10)?.round();
    final reps = _optionalRange(args, 'reps', '次数', min: 1, max: 100)?.round();
    final duration =
        _optionalRange(args, 'duration_sec', '时长', min: 5, max: 600)?.round();

    return AiTemplateItemInput(
      exerciseName: name,
      sets: sets ?? 3,
      // 只给了计时就按时长算；两者都没给时默认 10 次
      reps: reps ?? (duration == null ? 10 : null),
      durationSec: duration,
      category: optionalExerciseCategory(args),
      muscleGroup: optionalMuscleGroup(args),
    );
  }

  /// 是否顺手补齐缺失动作：默认 false（保持"缺动作就报错"的原行为）
  ///
  /// 无法解析的取值按 false 处理：宁可让用户先加动作，也不要静默多写几条库。
  static bool createMissingExercises(Map<String, dynamic> args) =>
      boolOf(args['create_missing_exercises']) ?? false;

  /// create_template 的完整入参
  static AiTemplateCommand template(Map<String, dynamic> args) {
    return AiTemplateCommand(
      name: templateName(args),
      difficulty: templateDifficulty(args),
      focus: templateFocus(args),
      minutes: templateMinutes(args),
      description: optionalTemplateDescription(args),
      items: templateItems(args),
      createMissingExercises: createMissingExercises(args),
    );
  }

  /// 一次最多新增的动作数（再多就该拆成两轮说；create_exercises 用）
  static const maxBatchExercises = 10;

  // ───────────── web_search（联网搜索） ─────────────

  /// 联网搜索关键词长度上限（DeepSeek 官方限制 1~128）
  static const maxWebQueryLength = 128;

  /// 联网搜索默认条数 / 上限（模型一次最多要 10 条，实际回传再压到 5 条）
  static const defaultWebSearchCount = 5;
  static const maxWebSearchCount = 10;

  /// 联网搜索关键词：非空、≤128 字
  static String webSearchQuery(Map<String, dynamic> args) {
    final raw = args['query'];
    final q = raw is String ? raw.trim() : '';
    if (q.isEmpty) throw const AiToolException('缺少搜索关键词');
    if (q.length > maxWebQueryLength) {
      throw const AiToolException('搜索关键词太长（128 字以内）');
    }
    return q;
  }

  /// 联网搜索条数：缺失默认 5，越界（1~10）抛异常
  static int webSearchCount(Map<String, dynamic> args) {
    final raw = args['count'];
    if (raw == null || (raw is String && raw.trim().isEmpty)) {
      return defaultWebSearchCount;
    }
    final v = lenientIntOf(raw);
    if (v == null) throw const AiToolException('搜索条数格式不正确');
    if (v < 1 || v > maxWebSearchCount) {
      throw const AiToolException('搜索条数不合理（应在 1~$maxWebSearchCount 条）');
    }
    return v;
  }

  // ───────────── fetch_url（读取网页） ─────────────

  /// 链接长度上限（官方限制 8192，App 侧收紧到 2048：正常文章链接远小于此）
  static const maxUrlLength = 2048;

  /// 链接不合法（协议 / 内网 / 带账号密码）时的统一文案
  static const unsafeUrlMessage = '这个链接不能抓取（内网或格式不支持）';

  /// 抓取链接的校验：只放行公网 http/https
  ///
  /// 拦的是「模型被诱导去读内网 / 本机」这类风险：
  /// - 协议必须是 http / https（拒绝 ftp:、file:、javascript: 等）
  /// - 必须带 host，且不能含用户名密码（`user:pass@host`）
  /// - host 不能是 localhost / 私有网段 / 链路本地 / IPv6 回环 / `.local`
  static Uri fetchUrl(Map<String, dynamic> args) {
    final raw = args['url'];
    final text = raw is String ? raw.trim() : '';
    if (text.isEmpty) throw const AiToolException('缺少网页链接');
    if (text.length > maxUrlLength) {
      throw const AiToolException(unsafeUrlMessage);
    }
    final uri = Uri.tryParse(text);
    if (uri == null) throw const AiToolException(unsafeUrlMessage);
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const AiToolException(unsafeUrlMessage);
    }
    if (uri.host.isEmpty) throw const AiToolException(unsafeUrlMessage);
    if (uri.userInfo.isNotEmpty) throw const AiToolException(unsafeUrlMessage);
    if (!isPublicHost(uri.host)) throw const AiToolException(unsafeUrlMessage);
    return uri;
  }

  /// host 是否指向公网（纯函数，便于单测）
  static bool isPublicHost(String host) {
    var h = host.trim().toLowerCase();
    // IPv6 的方括号：不同平台 / 写法下可能带也可能不带
    if (h.startsWith('[') && h.endsWith(']')) {
      h = h.substring(1, h.length - 1);
    }
    if (h.isEmpty) return false;
    if (h == 'localhost' || h.endsWith('.localhost')) return false;
    if (h.endsWith('.local')) return false;
    if (h == '::1' || h == '0:0:0:0:0:0:0:1') return false;
    if (h == '::' || h.endsWith('::1')) return false;
    if (h.startsWith('fe80:')) return false;

    final parts = h.split('.');
    if (parts.length == 4) {
      final octets = [for (final p in parts) int.tryParse(p)];
      // 不是点分十进制：按域名处理（交给下面的单段判断）
      if (octets.any((o) => o == null || o < 0 || o > 255)) {
        return h.contains('.');
      }
      final a = octets[0]!;
      final b = octets[1]!;
      if (a == 0 || a == 10 || a == 127) return false; // 0.0.0.0 / 10/8 / 回环
      if (a == 169 && b == 254) return false; // 链路本地
      if (a == 192 && b == 168) return false; // 192.168/16
      if (a == 172 && b >= 16 && b <= 31) return false; // 172.16~31/12
      return true;
    }
    // 单段主机名（如 http://intranet）几乎都指向内网，一律拒绝
    return h.contains('.');
  }

  // ───────────── start_workout（直接开练） ─────────────

  /// 模板名长度上限（与 create_template 保持一致）
  static const maxTemplateNameLength = 30;

  /// 休息时长范围（秒）：太短没意义，太长该去睡觉了
  static const minRestSec = 10;
  static const maxRestSec = 300;

  /// start_workout 的模板名（参数键是 `template_name`）：trim 后 1~30 字
  static String startWorkoutTemplateName(Map<String, dynamic> args) {
    final raw = args['template_name'];
    final name = raw is String ? raw.trim() : '';
    if (name.isEmpty) throw const AiToolException('缺少模板名称');
    if (name.length > maxTemplateNameLength) {
      throw const AiToolException('模板名称太长（30 字以内）');
    }
    return name;
  }

  /// start_workout 的可选休息时长（秒）：缺失返回 null（由用户设置兜底）
  static int? optionalRestSec(Map<String, dynamic> args) {
    final raw = args['rest_sec'];
    if (raw == null || (raw is String && raw.trim().isEmpty)) return null;
    final sec = lenientIntOf(raw);
    if (sec == null) throw const AiToolException('休息时长格式不正确');
    if (sec < minRestSec || sec > maxRestSec) {
      throw const AiToolException('休息时长不合理（应在 $minRestSec~$maxRestSec 秒之间）');
    }
    return sec;
  }

  // ───────────── create_exercises（批量新增动作） ─────────────

  /// 批量新增动作的入参：1~[maxBatchExercises] 个
  ///
  /// 同一批里同名（trim 后忽略大小写）的动作只保留第一个：
  /// 模型很容易把"深蹲"写两遍，这里先按批内去重，避免自己撞自己的查重规则。
  static List<AiExerciseInput> exercises(Map<String, dynamic> args) {
    final raw = args['exercises'];
    if (raw is! List || raw.isEmpty) {
      throw const AiToolException('至少要给 1 个动作');
    }
    if (raw.length > maxBatchExercises) {
      throw const AiToolException('一次最多新增 $maxBatchExercises 个动作');
    }
    final inputs = <AiExerciseInput>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! Map) throw const AiToolException('动作格式不正确');
      final input = exercise(Map<String, dynamic>.from(entry));
      if (seen.add(input.name.trim().toLowerCase())) inputs.add(input);
    }
    return inputs;
  }
}
