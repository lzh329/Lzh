import 'package:fittrack/features/ai/domain/ai_tool_router.dart';

/// 一条能力的展示文案
class AbilityText {
  /// 中文动作名（如「记录训练」）
  final String label;

  /// 一句示例说法（用户实际会怎么说）
  final String example;

  const AbilityText({required this.label, required this.example});
}

/// 只读能力（7 个，自动执行、不弹确认）
class ReadAbility {
  final String tool;
  final AbilityText text;
  const ReadAbility(this.tool, this.text);
}

/// 写能力（tool + action，需要确认卡）
class WriteAbility {
  final String tool;
  final String action;
  final AbilityText text;
  final bool destructive;
  const WriteAbility(this.tool, this.action, this.text, {this.destructive = false});

  String get key => '$tool:$action';
}

/// 「嘎教练能做什么」页面的**唯一数据源**
///
/// 防漂移：工具与 action 清单从 `AiMergedTools.actions` / `AiToolSpecs.readOnlyTools`
/// 现读，页面不许手抄工具名。新增 action 忘写文案时，[missingWriteKeys] 会报出来，
/// 对应测试立刻红 —— 页面本身则回退显示 action 原名，不至于空白。
class CoachAbilities {
  CoachAbilities._();

  /// 只读工具的文案（key = 工具名）
  static const Map<String, AbilityText> readTexts = {
    'query_stats': AbilityText(label: '查统计', example: '我这周练了几次？'),
    'search_food': AbilityText(label: '搜食物库', example: '牛肉面多少卡？'),
    'query_exercises': AbilityText(label: '查动作库', example: '有没有练背的动作'),
    'query_measurements': AbilityText(label: '查围度', example: '我腰围多少了'),
    'query_workouts': AbilityText(label: '查训练记录', example: '上周三练了什么'),
    'web_search': AbilityText(label: '联网搜索', example: '最新的减脂研究怎么说'),
    'fetch_url': AbilityText(label: '读网页', example: '帮我看看这个链接写什么'),
  };

  /// 写工具的文案（key = 'tool:action'）
  static const Map<String, AbilityText> writeTexts = {
    'workout:log': AbilityText(label: '记录训练', example: '用「胸腿日」模板补记 11 月 2 号的训练'),
    'workout:update': AbilityText(label: '修改训练记录', example: '昨天那次训练改成 40 分钟'),
    'workout:delete': AbilityText(label: '删除训练记录', example: '删掉昨天那条训练记录'),
    'workout:start': AbilityText(label: '开始训练', example: '用「腿日」模板开练'),
    'body:weight': AbilityText(label: '记录体重', example: '今天称了 150 斤'),
    'body:measurements': AbilityText(label: '记录围度', example: '腰围 80 了'),
    'body:update_measurement': AbilityText(label: '修改围度', example: '昨天腰围记错了，改成 79'),
    'body:delete_measurement': AbilityText(label: '删除围度', example: '删掉昨天那条腰围'),
    'diet:food': AbilityText(label: '记录饮食', example: '中午吃了一碗牛肉面'),
    'diet:water': AbilityText(label: '记录喝水', example: '今天喝了 6 杯水'),
    'settings:target_weight': AbilityText(label: '设置目标体重', example: '我的目标是 140 斤'),
    'settings:diet_target': AbilityText(label: '设置饮食目标', example: '每天 1600 千卡'),
    'settings:profile': AbilityText(label: '更新身体资料', example: '我身高 175'),
    'settings:reminder': AbilityText(label: '设置提醒', example: '每天晚上 8 点提醒我称重'),
    'template:create': AbilityText(label: '新建训练模板', example: '帮我建个「胸腿日」模板'),
    'template:delete': AbilityText(label: '删除训练模板', example: '删掉「腿日」模板'),
    'exercise:create': AbilityText(label: '新增动作', example: '帮我加个动作叫波比跳'),
    'exercise:create_many': AbilityText(label: '批量新增动作', example: '把这几个动作都加进库'),
    'goal:create': AbilityText(label: '新建目标', example: '帮我定个 3 个月减到 130 斤的目标'),
    'goal:complete': AbilityText(label: '完成目标', example: '第一个目标达成了'),
    'goal:delete': AbilityText(label: '删除目标', example: '删掉那个目标'),
    'erase:records': AbilityText(label: '删除某天记录', example: '删掉 11 月 2 号那天的记录'),
    'erase:all': AbilityText(label: '清空全部数据', example: '清空我的所有数据'),
  };

  /// 只读清单：按 [AiToolSpecs.readOnlyTools] 的声明顺序渲染
  static List<ReadAbility> readAbilities() => [
        for (final tool in AiToolSpecsOrder.readOnly)
          ReadAbility(tool, readTexts[tool] ?? AbilityText(label: tool, example: '')),
      ];

  /// 写清单：按 [AiMergedTools.actions] 的顺序渲染（不手抄）
  static List<WriteAbility> writeAbilities() {
    final out = <WriteAbility>[];
    for (final entry in AiMergedTools.actions.entries) {
      for (final action in entry.value) {
        final key = '${entry.key}:$action';
        out.add(WriteAbility(
          entry.key,
          action,
          writeTexts[key] ?? AbilityText(label: action, example: ''),
          destructive: isMergedDestructive(entry.key, action),
        ));
      }
    }
    return out;
  }

  /// 没写文案的写 action（测试用；为空才允许上线）
  static List<String> missingWriteKeys() => [
        for (final entry in AiMergedTools.actions.entries)
          for (final action in entry.value)
            if (!writeTexts.containsKey('${entry.key}:$action'))
              '${entry.key}:$action',
      ];

  /// 没写文案的只读工具
  static List<String> missingReadKeys() => [
        for (final tool in AiToolSpecsOrder.readOnly)
          if (!readTexts.containsKey(tool)) tool,
      ];

  /// 对话之外自动发生的事
  static const List<AbilityText> automatic = [
    AbilityText(label: '主动关心', example: '每周主动问你一句近况'),
    AbilityText(label: '训练周报', example: '每周汇总训练次数与时长'),
    AbilityText(label: '记住你说过的事', example: '记住你的伤病、偏好、作息'),
    AbilityText(label: '朗读', example: '语音教练把你的话读出来'),
    AbilityText(label: '首页角色形象', example: '首页陪着你练的那个形象'),
  ];
}

/// 只读工具名的稳定顺序（避免页面直接依赖 Set 的迭代顺序）
class AiToolSpecsOrder {
  AiToolSpecsOrder._();

  static const List<String> readOnly = [
    'query_stats',
    'search_food',
    'query_exercises',
    'query_measurements',
    'query_workouts',
    'web_search',
    'fetch_url',
  ];
}
