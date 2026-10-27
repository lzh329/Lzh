/// 工具名常量、OpenAI function schema 与工具分类（纯数据，便于单测）
class AiToolSpecs {
  AiToolSpecs._();

  // ── 记录类（写，需确认） ──
  static const logWeight = 'log_weight';
  static const logWater = 'log_water';
  static const logFood = 'log_food';
  static const logWorkout = 'log_workout';
  static const logMeasurements = 'log_measurements';

  // ── 设置类（写，需确认） ──
  static const setTargetWeight = 'set_target_weight';
  static const updateProfile = 'update_profile';
  static const setDietTarget = 'set_diet_target';
  static const setReminder = 'set_reminder';

  // ── 管理类（写，需确认；delete_records 为危险操作） ──
  static const manageGoal = 'manage_goal';
  static const deleteRecords = 'delete_records';

  // ── 只读类（自动执行） ──
  static const queryStats = 'query_stats';
  static const searchFood = 'search_food';

  /// 危险工具（删除数据）：确认卡必须用警示样式
  static const Set<String> destructiveTools = {deleteRecords};

  /// 只读工具：无需用户确认，直接执行
  static const Set<String> readOnlyTools = {queryStats, searchFood};

  /// 需要用户确认的写操作
  static const Set<String> writeTools = {
    logWeight,
    logWater,
    logFood,
    logWorkout,
    logMeasurements,
    setTargetWeight,
    updateProfile,
    setDietTarget,
    setReminder,
    manageGoal,
    deleteRecords,
  };

  static bool isDestructive(String name) => destructiveTools.contains(name);

  static bool isReadOnly(String name) => readOnlyTools.contains(name);

  /// 暴露给模型的工具清单（13 个：11 个写操作 + 2 个只读查询）
  static const defs = <Map<String, dynamic>>[
    // ───────── 记录类 ─────────
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
            'cups': {'type': 'integer', 'description': '今天累计杯数，1~30'},
          },
          'required': ['cups'],
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
            'grams': {'type': 'number', 'description': '估算重量（克），1~2000'},
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
            'minutes': {'type': 'integer', 'description': '训练时长（分钟），1~300'},
            'note': {
              'type': 'string',
              'description': '训练内容简述，如"深蹲 4 组 × 12 次、卧推 4 组 × 10 次"',
            },
          },
          'required': ['workout_type', 'minutes'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': logMeasurements,
        'description': '记录腰围 / 臀围 / 胸围围度。用户说"腰围 80 了""量了下三围"时调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'waist_cm': {'type': 'number', 'description': '腰围（厘米），30~200'},
            'hip_cm': {'type': 'number', 'description': '臀围（厘米），30~200'},
            'chest_cm': {'type': 'number', 'description': '胸围（厘米），30~200'},
            'weight_jin': {
              'type': 'number',
              'description': '同时记录的体重（斤），40~600；不给就用最新一次体重',
            },
            'date': {
              'type': 'string',
              'description': '日期 YYYY-MM-DD，默认今天；不允许未来日期',
            },
          },
          'required': [],
        },
      },
    },
    // ───────── 设置类 ─────────
    {
      'type': 'function',
      'function': {
        'name': setTargetWeight,
        'description': '设置用户的体重目标（"我想瘦到 140 斤""定个目标 140 斤"）。',
        'parameters': {
          'type': 'object',
          'properties': {
            'target_jin': {
              'type': 'number',
              'description': '目标体重，单位斤，40~600',
            },
          },
          'required': ['target_jin'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': updateProfile,
        'description': '更新身体信息（身高 / 性别 / 出生年份），用于算 BMI 与基础代谢。',
        'parameters': {
          'type': 'object',
          'properties': {
            'height_cm': {'type': 'number', 'description': '身高（厘米），100~250'},
            'gender': {
              'type': 'string',
              'enum': ['male', 'female'],
              'description': '性别：男 / 女',
            },
            'birth_year': {
              'type': 'integer',
              'description': '出生年份，如 1995；1920 到（今年-10）之间',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': setDietTarget,
        'description': '设置每日饮食目标（热量与三大宏量）。用户说"每天吃 1800 千卡"时调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'calories': {
              'type': 'integer',
              'description': '每日热量目标（千卡），800~5000',
            },
            'protein_g': {'type': 'number', 'description': '每日蛋白目标（克），0~500'},
            'carbs_g': {'type': 'number', 'description': '每日碳水目标（克），0~500'},
            'fat_g': {'type': 'number', 'description': '每日脂肪目标（克），0~500'},
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': setReminder,
        'description': '开启 / 关闭每日称重提醒，可指定时间。用户说"每天 9 点提醒我称重"时调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'enabled': {
              'type': 'boolean',
              'description': 'true 开启每日提醒，false 关闭',
            },
            'hour': {'type': 'integer', 'description': '提醒小时 0~23，默认 9'},
            'minute': {'type': 'integer', 'description': '提醒分钟 0~59，默认 0'},
          },
          'required': ['enabled'],
        },
      },
    },
    // ───────── 管理类 ─────────
    {
      'type': 'function',
      'function': {
        'name': manageGoal,
        'description': '管理训练 / 体重目标：新建、标记完成、删除。不确定 id 时先 query_stats。',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['create', 'complete', 'delete'],
              'description': 'create 新建 / complete 标记完成 / delete 删除',
            },
            'goal_id': {
              'type': 'integer',
              'description': '目标 id（complete / delete 必填，来自 query_stats 的 goals）',
            },
            'type': {
              'type': 'string',
              'enum': ['weight', 'frequency', 'custom'],
              'description': '目标类型（create 必填）：体重 / 训练频率 / 自定义',
            },
            'target_value': {
              'type': 'number',
              'description': '目标数值（create 必填，大于 0）；体重目标的单位是斤',
            },
            'category': {
              'type': 'string',
              'description': '自定义目标的分类标签，可省略',
            },
            'end_date': {
              'type': 'string',
              'description': '结束日期 YYYY-MM-DD，可省略',
            },
          },
          'required': ['action'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': deleteRecords,
        'description': '删除某一天的记录（体重 / 饮食 / 训练 / 饮水）。危险操作，先说清后果。',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['weight', 'food', 'workout', 'water'],
              'description': '要删除的记录类型',
            },
            'date': {
              'type': 'string',
              'description': '日期 YYYY-MM-DD，默认今天；不允许未来日期',
            },
          },
          'required': ['type'],
        },
      },
    },
    // ───────── 只读类 ─────────
    {
      'type': 'function',
      'function': {
        'name': queryStats,
        'description':
            '查询用户的体重、训练、饮水、饮食统计与目标列表（只读，不修改数据）',
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
        'name': searchFood,
        'description': '在食物库里搜索食物的热量（只读）。想确认热量再记录时先搜一下。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词，如"牛肉面"，20 字以内',
            },
          },
          'required': ['query'],
        },
      },
    },
  ];
}
