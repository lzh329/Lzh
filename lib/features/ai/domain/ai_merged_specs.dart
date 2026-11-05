import 'package:fittrack/features/ai/domain/ai_tool_router.dart';

/// 合并后的 8 个写工具 schema（模型看到的面）
///
/// 为什么不塞回 `ai_tool_specs.dart`：那个文件已经 900+ 行，再加 8 段 schema
/// 会到 1200 行，谁都不敢改。这里只放"模型看到什么"，语义映射全在
/// `ai_tool_router.dart` 的 `_routeTable`（唯一翻译点）。
///
/// 参数**平铺**、按 action 说明用途 —— 不用 `oneOf`：DeepSeek 对 oneOf 支持
/// 不稳，历史上出现过直接被网关拒掉的情况。
const List<Map<String, dynamic>> mergedWriteDefs = [
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.workout,
      'description': '训练记录：log 记一次训练 / update 改记录 / delete 删记录 / '
          'start 开始练某个模板。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['log', 'update', 'delete', 'start'],
            'description': 'log 记训练 / update 改训练 / delete 删训练 / start 开练模板',
          },
          'date': {
            'type': 'string',
            'description': '日期 YYYY-MM-DD（log 用；默认今天，不允许未来）',
          },
          'workout_type': {
            'type': 'string',
            'enum': ['力量', '有氧', '拉伸', '其他'],
            'description': '训练类型（log 用）',
          },
          'minutes': {
            'type': 'integer',
            'description': '训练时长（分钟，log/update 用）',
          },
          'note': {'type': 'string', 'description': '备注（log/update 用）'},
          'template_name': {
            'type': 'string',
            'description': '模板名。log 时按模板补记（组次/时长由模板决定，'
                '此时不用列 exercises）；start 时是要开练的模板',
          },
          'exercises': {
            'type': 'array',
            'description': '动作清单（log 且没给 template_name 时用）。'
                '动作名必须在动作库里；力量给 reps，有氧/拉伸给 minutes',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'sets': {'type': 'integer', 'description': '组数，默认 1'},
                'reps': {'type': 'integer', 'description': '每组次数（力量必填）'},
                'minutes': {
                  'type': 'number',
                  'description': '每组时长分钟（有氧/拉伸用，可小数，如 0.5 = 30 秒）',
                },
                'seconds': {
                  'type': 'integer',
                  'description': '每组时长秒（有氧/静力用，5~600）。用户说'
                      '"做 30 秒"就直接传 30，不要折算成次数；'
                      '与 minutes 同时给时以 seconds 为准',
                },
                'weight_kg': {'type': 'number'},
              },
              'required': ['name'],
            },
          },
          'workout_id': {
            'type': 'integer',
            'description': '训练记录 id（update/delete 必填，先用 query_workouts 查）',
          },
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.body,
      'description': '身体数据：weight 记体重 / measurements 记围度 / '
          'update_measurement 改一条围度 / delete_measurement 删一条围度。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': [
              'weight',
              'measurements',
              'update_measurement',
              'delete_measurement'
            ],
            'description': 'weight 记体重 / measurements 记围度 / '
                'update_measurement 改围度 / delete_measurement 删围度',
          },
          'weight_jin': {
            'type': 'number',
            'description': '体重（斤），weight 必填，40~600',
          },
          'date': {'type': 'string', 'description': '日期 YYYY-MM-DD'},
          'waist_cm': {'type': 'number', 'description': '腰围（cm），measurements 用'},
          'hip_cm': {'type': 'number', 'description': '臀围（cm）'},
          'chest_cm': {'type': 'number', 'description': '胸围（cm）'},
          'id': {
            'type': 'integer',
            'description': '围度记录 id（update_measurement / delete_measurement 必填，'
                '先用 query_measurements 查）',
          },
          'part': {
            'type': 'string',
            'description': 'update_measurement 要改的部位（waist/hip/chest…）',
          },
          'value': {'type': 'number', 'description': 'update_measurement 的新数值'},
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.diet,
      'description': '饮食与饮水：food 记一顿饭 / water 记喝水杯数。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['food', 'water'],
            'description': 'food 记饮食 / water 记饮水',
          },
          'food_name': {'type': 'string', 'description': '食物名，food 必填'},
          'calories': {'type': 'number', 'description': '热量 kcal（food 用）'},
          'meal_type': {
            'type': 'string',
            'description': '早餐/午餐/晚餐/加餐（food 用，默认按时间推断）',
          },
          'cups': {'type': 'integer', 'description': '今天累计杯数（water 必填，1~30）'},
          'date': {'type': 'string', 'description': '日期 YYYY-MM-DD'},
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.settings,
      'description': '用户设置：target_weight 目标体重 / diet_target 饮食目标 / '
          'profile 身高生日等资料 / reminder 提醒时间。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['target_weight', 'diet_target', 'profile', 'reminder'],
          },
          'target_weight_jin': {'type': 'number', 'description': '目标体重（斤）'},
          'daily_calorie_target': {'type': 'integer', 'description': '每日热量目标'},
          'protein_target_g': {'type': 'number'},
          'carbs_target_g': {'type': 'number'},
          'fat_target_g': {'type': 'number'},
          'height_cm': {'type': 'number'},
          'birth_date': {'type': 'string', 'description': '生日 YYYY-MM-DD'},
          'gender': {'type': 'string', 'enum': ['male', 'female']},
          'activity_level': {
            'type': 'string',
            'enum': ['sedentary', 'light', 'moderate', 'active', 'very_active'],
          },
          'reminder_enabled': {'type': 'boolean'},
          'reminder_hour': {'type': 'integer'},
          'reminder_minute': {'type': 'integer'},
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.template,
      'description': '训练模板：create 新建 / delete 删除。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['create', 'delete'],
          },
          'name': {'type': 'string', 'description': '模板名（create 必填）'},
          'difficulty': {
            'type': 'string',
            'enum': ['入门', '中阶', '高阶'],
            'description': '难度（create 用，默认入门）',
          },
          'minutes': {'type': 'integer', 'description': '预计时长（分钟）'},
          'items': {
            'type': 'array',
            'description': '动作清单（create 用，1~40 项）',
            'items': {
              'type': 'object',
              'properties': {
                'exercise_name': {'type': 'string'},
                'sets': {'type': 'integer'},
                'reps': {'type': 'integer'},
                'minutes': {'type': 'number', 'description': '每组分钟（有氧/拉伸，可小数）'},
                'seconds': {
                  'type': 'integer',
                  'description': '每组秒（计时类动作，5~600）；用户说"做 30 秒"就传 30',
                },
              },
              'required': ['exercise_name'],
            },
          },
          'id': {'type': 'integer', 'description': '模板 id（delete 必填）'},
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.exercise,
      'description': '动作库：create 新增一个动作 / create_many 批量新增。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['create', 'create_many'],
          },
          'name': {'type': 'string', 'description': '动作名（create 必填）'},
          'category': {
            'type': 'string',
            'enum': ['strength', 'cardio', 'stretch'],
            'description': '分类：力量/有氧/拉伸',
          },
          'default_reps': {'type': 'integer'},
          'default_duration_sec': {'type': 'integer'},
          'exercises': {
            'type': 'array',
            'description': '批量新增清单（create_many 用）',
            'items': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
                'category': {'type': 'string'},
              },
              'required': ['name'],
            },
          },
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.goal,
      'description': '目标管理：create 新建 / complete 完成 / delete 删除。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['create', 'complete', 'delete'],
          },
          'goal_id': {'type': 'integer', 'description': '目标 id（complete/delete 必填）'},
          'type': {
            'type': 'string',
            'enum': ['weight', 'frequency', 'custom'],
            'description': '目标类型（create 必填）',
          },
          'target_value': {'type': 'number', 'description': '目标数值（体重目标单位是斤）'},
          'category': {'type': 'string', 'description': '自定义目标分类，可省略'},
          'end_date': {'type': 'string', 'description': '结束日期 YYYY-MM-DD'},
        },
        'required': ['action'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': AiMergedTools.erase,
      'description': '删除数据：records 删某一天的记录 / all 清空全部数据（危险）。',
      'parameters': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['records', 'all'],
            'description': 'records 删某天记录 / all 清空全部（毁灭性）',
          },
          'type': {
            'type': 'string',
            'enum': ['weight', 'food', 'workout', 'water'],
            'description': 'records 要删的记录类型',
          },
          'date': {'type': 'string', 'description': '日期 YYYY-MM-DD（records 用）'},
          'confirm': {
            'type': 'boolean',
            'description': 'all 时必须为 true（二次确认）',
          },
        },
        'required': ['action'],
      },
    },
  },
];
