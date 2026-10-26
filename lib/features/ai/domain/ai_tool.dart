import 'dart:convert';

/// 模型请求的一次工具调用
class AiToolCall {
  final String id;
  final String name;
  final String argumentsJson; // 模型返回的 JSON 字符串（可能不完整/非法）

  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  Map<String, dynamic> get arguments {
    try {
      final v = jsonDecode(argumentsJson);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// 工具调用的执行预览（用于确认卡片）
class AiToolPreview {
  final AiToolCall call;
  final String label; // 记录体重
  final String detail; // 161.0 斤 · 今天
  final bool needsConfirm; // 写操作需确认，查询类直接执行

  const AiToolPreview({
    required this.call,
    required this.label,
    required this.detail,
    required this.needsConfirm,
  });
}

/// 工具调用不合法（参数越界 / 未知工具）——由 App 侧拦截，模型无法绕过
class AiToolException implements Exception {
  final String message;
  const AiToolException(this.message);

  @override
  String toString() => message;
}

/// 工具名常量与 OpenAI function schema
class AiToolSpecs {
  AiToolSpecs._();

  static const logWeight = 'log_weight';
  static const logWater = 'log_water';
  static const queryStats = 'query_stats';
  static const logFood = 'log_food';
  static const logWorkout = 'log_workout';

  /// 暴露给模型的工具清单（只读查询 + 两项写操作）
  static const defs = <Map<String, dynamic>>[
    {
      'type': 'function',
      'function': {
        'name': logWeight,
        'description': '记录用户某一天称的体重。用户明确说"我称了/体重是 xx 斤"时才调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'weight_jin': {
              'type': 'number',
              'description': '体重，单位斤（1 斤 = 0.5 公斤），范围 40~600',
            },
            'date': {
              'type': 'string',
              'description': '日期 YYYY-MM-DD，默认今天；不允许未来日期',
            },
          },
          'required': ['weight_jin'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': logWater,
        'description': '记录用户今天喝了几杯水（每杯约 200ml）',
        'parameters': {
          'type': 'object',
          'properties': {
            'cups': {
              'type': 'integer',
              'description': '今天累计杯数，1~30',
            },
          },
          'required': ['cups'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': queryStats,
        'description': '查询用户的体重、训练、饮水、饮食统计（只读，不修改数据）',
        'parameters': {
          'type': 'object',
          'properties': {
            'range': {
              'type': 'string',
              'enum': ['week', 'month', 'all'],
              'description': '统计范围：本周 / 本月 / 全部',
            },
          },
          'required': ['range'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': logFood,
        'description': '记录用户吃了什么。需要你估算每 100 克热量后一起提交。',
        'parameters': {
          'type': 'object',
          'properties': {
            'food_name': {
              'type': 'string',
              'description': '食物名称，如"牛肉面""米饭"',
            },
            'grams': {
              'type': 'number',
              'description': '估算重量（克），1~2000',
            },
            'meal_type': {
              'type': 'string',
              'enum': ['breakfast', 'lunch', 'dinner', 'snack'],
              'description': '餐次：早餐/午餐/晚餐/加餐',
            },
            'calories_per_100g': {
              'type': 'number',
              'description': '你估算的每 100 克热量（千卡），0~900',
            },
          },
          'required': ['food_name', 'grams', 'meal_type', 'calories_per_100g'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': logWorkout,
        'description': '记录用户完成的一次训练（自由度较高的记录，不细分每组动作）',
        'parameters': {
          'type': 'object',
          'properties': {
            'workout_type': {
              'type': 'string',
              'enum': ['力量', '有氧', '拉伸', '其他'],
              'description': '训练类型',
            },
            'minutes': {
              'type': 'integer',
              'description': '训练时长（分钟），1~300',
            },
            'note': {
              'type': 'string',
              'description': '训练内容简述，如"深蹲 4 组 × 12 次、卧推 4 组 × 10 次"',
            },
          },
          'required': ['workout_type', 'minutes'],
        },
      },
    },
  ];
}

/// 参数解析与校验（纯函数，便于单测）
class AiToolArgs {
  AiToolArgs._();

  /// 体重（斤）→ 公斤，校验 40~600 斤
  static double weightKg(Map<String, dynamic> args) {
    final v = args['weight_jin'];
    final jin = v is num ? v.toDouble() : double.tryParse('$v');
    if (jin == null) throw const AiToolException('缺少体重数值');
    if (jin < 40 || jin > 600) {
      throw const AiToolException('体重数值不合理（应在 40~600 斤）');
    }
    return jin / 2;
  }

  static double weightJin(Map<String, dynamic> args) =>
      weightKg(args) * 2;

  /// 杯数，校验 1~30
  static int cups(Map<String, dynamic> args) {
    final v = args['cups'];
    final cups = v is num ? v.toInt() : int.tryParse('$v');
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
    final v = args['grams'];
    final grams = v is num ? v.toDouble() : double.tryParse('$v');
    if (grams == null) throw const AiToolException('缺少重量');
    if (grams < 1 || grams > 2000) {
      throw const AiToolException('重量不合理（应在 1~2000 克）');
    }
    return grams;
  }

  /// 每 100 克热量，0~900
  static double caloriesPer100g(Map<String, dynamic> args) {
    final v = args['calories_per_100g'];
    final c = v is num ? v.toDouble() : double.tryParse('$v');
    if (c == null) throw const AiToolException('缺少热量估算');
    if (c < 0 || c > 900) {
      throw const AiToolException('热量数值不合理（应在 0~900 千卡/100g）');
    }
    return c;
  }

  /// 餐次：非法或缺失时按当前时间推断
  static String mealType(Map<String, dynamic> args) {
    final raw = args['meal_type'];
    if (raw is String && const ['breakfast', 'lunch', 'dinner', 'snack'].contains(raw)) {
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
    final v = args['minutes'];
    final m = v is num ? v.toInt() : int.tryParse('$v');
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
}
