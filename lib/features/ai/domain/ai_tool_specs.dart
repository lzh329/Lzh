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

  // ── 动作库 / 模板类（create_* 写需确认，query_exercises 只读） ──
  static const createExercise = 'create_exercise';
  static const createExercises = 'create_exercises';
  static const createTemplate = 'create_template';

  // ── 只读类（自动执行） ──
  static const queryStats = 'query_stats';
  static const searchFood = 'search_food';
  static const queryExercises = 'query_exercises';

  // ── 联网类（只读，自动执行） ──
  static const webSearch = 'web_search';
  static const fetchUrl = 'fetch_url';

  /// 危险工具（删除数据）：确认卡必须用警示样式
  static const Set<String> destructiveTools = {deleteRecords};

  /// 只读工具：无需用户确认，直接执行
  ///
  /// 联网搜索 / 读网页也只读：不碰本地数据，不需要确认卡。
  static const Set<String> readOnlyTools = {
    queryStats,
    searchFood,
    queryExercises,
    webSearch,
    fetchUrl,
  };

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
    createExercise,
    createExercises,
    createTemplate,
  };

  static bool isDestructive(String name) => destructiveTools.contains(name);

  static bool isReadOnly(String name) => readOnlyTools.contains(name);

  /// 联网类工具（web_search / fetch_url）——「联网搜索」开关关闭时整体摘掉
  static const Set<String> webTools = {webSearch, fetchUrl};

  /// 按「联网搜索」开关裁剪后的工具清单
  ///
  /// [webEnabled] 为 false 时把 [webSearch] / [fetchUrl] 两个 schema 摘掉
  /// （19 → 17）：模型看不到这两个工具，就没法调，也就不会产生搜索费用。
  /// [defs] 本身保持 19 个不变（单测锁全集、执行器仍认识这两个名字）。
  static List<Map<String, dynamic>> defsFor({required bool webEnabled}) {
    if (webEnabled) return defs;
    return [
      for (final def in defs)
        if (!webTools.contains(_nameOf(def))) def,
    ];
  }

  /// 取一条 function schema 的工具名（结构固定，取不到就返回空串）
  static String _nameOf(Map<String, dynamic> def) {
    final function = def['function'];
    if (function is! Map) return '';
    final name = function['name'];
    return name is String ? name : '';
  }

  /// 暴露给模型的工具清单（19 个：14 个写操作 + 5 个只读工具）
  ///
  /// ⚠️ 没有必填参数的工具**不要**写 `'required': []`：
  /// 空数组会被部分 OpenAI 兼容网关判为非法 schema 并返回 400，直接省略该键即可。
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
    {
      'type': 'function',
      'function': {
        'name': queryExercises,
        'description': '查看动作库里有哪些动作（只读）。建训练模板前、或不确定某个动作是否已在库里时先查。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '动作名关键词，如"深蹲"，20 字以内；不给则列出前 8 个动作',
            },
            'category': {
              'type': 'string',
              'enum': ['bodyweight', 'gym', 'cardio', 'stretch'],
              'description': '分类筛选：徒手 / 器械 / 有氧 / 拉伸，可省略',
            },
          },
        },
      },
    },
    // ───────── 动作库 / 模板类（写，需确认） ─────────
    {
      'type': 'function',
      'function': {
        'name': createExercise,
        'description':
            '往动作库里新增一个自定义动作。动作库里没有这个动作、但用户想练 / 想加进模板时调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': '动作名称，如"保加利亚分腿蹲"，1~30 字',
            },
            'category': {
              'type': 'string',
              'enum': ['bodyweight', 'gym', 'cardio', 'stretch'],
              'description': '分类：徒手 / 器械 / 有氧 / 拉伸',
            },
            'muscle_group': {
              'type': 'string',
              'description': '目标肌群，如"腿部""胸部"，10 字以内，可省略',
            },
            'default_reps': {
              'type': 'integer',
              'description': '默认次数，1~100，可省略',
            },
            'default_duration_sec': {
              'type': 'integer',
              'description': '默认时长（秒），5~600，可省略；计时类动作用',
            },
          },
          'required': ['name', 'category'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': createExercises,
        'description':
            '一次往动作库批量新增多个动作（最多 10 个）。用户一次列出好几个库里没有的动作时用这个，'
                '不要逐个调用 create_exercise。同名动作会自动跳过。',
        'parameters': {
          'type': 'object',
          'properties': {
            'exercises': {
              'type': 'array',
              'description': '要新增的动作，1~10 个',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {
                    'type': 'string',
                    'description': '动作名称，如"开合跳"，1~30 字',
                  },
                  'category': {
                    'type': 'string',
                    'enum': ['bodyweight', 'gym', 'cardio', 'stretch'],
                    'description': '分类：徒手 / 器械 / 有氧 / 拉伸',
                  },
                  'muscle_group': {
                    'type': 'string',
                    'description': '目标肌群，如"腿部"，10 字以内，可省略',
                  },
                  'default_reps': {
                    'type': 'integer',
                    'description': '默认次数，1~100，可省略',
                  },
                  'default_duration_sec': {
                    'type': 'integer',
                    'description': '默认时长（秒），5~600，可省略；计时类动作用',
                  },
                },
                'required': ['name', 'category'],
              },
            },
          },
          'required': ['exercises'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': createTemplate,
        'description':
            '新建一个训练模板（一组动作 + 组数次数）。用户一次列出多个动作要建模板时，'
                '直接一次调用本工具：把 create_missing_exercises 设成 true，'
                '动作的 category / muscle_group 一并给出，缺失的动作会和模板在同一次确认里一起建好。',
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {
              'type': 'string',
              'description': '模板名称，如"下肢力量"，1~30 字',
            },
            'difficulty': {
              'type': 'string',
              'enum': ['入门', '中阶', '高阶'],
              'description': '难度：入门 / 中阶 / 高阶',
            },
            'focus': {
              'type': 'string',
              'enum': ['全身', '放松', '碎片'],
              'description': '侧重：全身 / 放松 / 碎片（碎片=碎片时间短练）',
            },
            'minutes': {
              'type': 'integer',
              'description': '预计时长（分钟），5~180',
            },
            'description': {
              'type': 'string',
              'description': '一句话说明，100 字以内，可省略',
            },
            'create_missing_exercises': {
              'type': 'boolean',
              'description': 'true = 动作库里没有的动作在同一次确认里先建好再建模板；'
                  'false / 省略 = 缺动作时直接失败，需要你先 create_exercise',
            },
            'items': {
              'type': 'array',
              'description': '动作列表，1~12 项',
              'items': {
                'type': 'object',
                'properties': {
                  'exercise_name': {
                    'type': 'string',
                    'description': '动作名，须与动作库里的名称一致',
                  },
                  'sets': {
                    'type': 'integer',
                    'description': '组数，1~10，默认 3',
                  },
                  'reps': {
                    'type': 'integer',
                    'description': '每组次数，1~100',
                  },
                  'duration_sec': {
                    'type': 'integer',
                    'description': '每组时长（秒），5~600；计时类动作（平板支撑等）用',
                  },
                  'category': {
                    'type': 'string',
                    'enum': ['bodyweight', 'gym', 'cardio', 'stretch'],
                    'description': '仅当这个动作库里没有、需要新建时用：分类（徒手 / 器械 / 有氧 / 拉伸）',
                  },
                  'muscle_group': {
                    'type': 'string',
                    'description': '仅当这个动作需要新建时用：目标肌群，如"腿部"，10 字以内',
                  },
                },
                'required': ['exercise_name'],
              },
            },
          },
          'required': ['name', 'difficulty', 'focus', 'minutes', 'items'],
        },
      },
    },
    // ───────── 联网类（只读，自动执行） ─────────
    {
      'type': 'function',
      'function': {
        'name': webSearch,
        'description': '联网搜索最新信息（只读）。新闻、价格、赛事、政策、产品发布这类'
            '有时效性的事实先搜一下，别凭记忆答。',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': '搜索关键词，1~128 字，写清楚要查什么',
            },
            'count': {
              'type': 'integer',
              'description': '要几条结果，1~10，默认 5；回传给模型的最多 5 条',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': fetchUrl,
        'description': '读取一个公开网页的正文（只读，返回 Markdown）。用户发来链接、'
            '或需要看搜索结果全文时调用。',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': '要读取的网址，必须是 http / https 公网链接（内网地址读不了）',
            },
          },
          'required': ['url'],
        },
      },
    },
  ];
}
