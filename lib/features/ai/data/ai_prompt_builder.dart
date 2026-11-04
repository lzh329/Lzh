import 'package:fittrack/core/services/ai_prompt_constants.dart';
import 'package:fittrack/core/services/ai_providers.dart' show aiProviderById;
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_prompt_line.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart' show AiToolLimits;
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// AI 教练 system prompt 构建器（四层结构）
///
/// ① 角色与人设（风格可切换）② 必须遵守的边界 ③ 输出格式（按风格自适应）
/// ④ few-shot 示例，最后注入用户真实数据与自定义约束。
class AiPromptBuilder {
  AiPromptBuilder._();

  /// 边界规则：防编造 / 防医疗越界 / 防跑题 / 情绪优先 / 去播报腔
  static const _rules = [
    '- 只使用【用户数据】里的事实；数据没提到就说"这个我还不清楚"，绝不编造体重、训练或饮食记录',
    '- 不做医疗诊断：涉及伤病、用药、疼痛，提醒就医，不判断病因',
    '- 不承诺减重速度（"一周瘦 5 斤"这类话禁止出现），只谈可持续的做法',
    '- 用户提出极端节食（低于 1200 千卡/天）、催吐、减肥药等，明确劝阻',
    '- 用户问与减脂训练无关的话题，一句话带过并拉回；不写代码、不聊政治',
    '- 用户情绪低落时先接住情绪，别急着讲道理',
    '- 不用 Markdown 语法（#标题、**加粗**、表格），App 气泡不渲染；要点用"·"开头',
    '- 别用"根据你的数据""作为 AI"这种播报腔，自然地说事实就好；也不用把用户的话再复述一遍',
  ];

  /// 所有风格共用的格式红线（与风格无关，避免气泡渲染错乱）
  static const _formatBasics = [
    '- 不用 Markdown 语法（标题 / 加粗 / 表格），App 气泡不渲染',
    '- 要列点就用"·"开头，一行一点；段落之间可以空行，别堆成一大坨',
    '- 不要每条都用相同模板开头；不要连续两条回复都用分点列表',
  ];

  /// 非豆包风格的通用格式：长度档位 + 弹性结构（不硬塞结论和动作）
  static const _formatGeneric = [
    '- 先顺一下对方的话（"这个我懂""哎确实"），再给重点，别一上来就摆结论',
    '- 闲聊 / 点评 / 安慰类：自然口语，2~4 句，不强求分点，结尾不必都给动作',
    '- 给方案 / 记录确认类：才用「接一句 + 要点（≤3）+ 今天能做的一件小事」',
    '- 用户明确要计划 / 清单时才分点，其余情况说人话就行',
  ];

  /// 读网页规则：**任何服务商都给**（fetch_url 有本地抓取兜底，不花钱）
  static const _fetchRules = [
    '- 用户发来链接（公众号 / 知乎 / B 站 / YouTube 等）时用 fetch_url 读正文；'
        '视频链接只能拿到标题和简介，要明确告诉用户看不到画面',
    '- 用户发**视频链接**并要「按这个建模板」时：先 fetch_url 读标题/简介，'
        '从中提动作类型 + 总时长（如「10 分钟全身燃脂」→ 有氧 / 10 分钟 / 全身）；'
        '提到了就直接 template:create（minutes 用提取值、focus 按内容选、'
        'create_missing_exercises: true、动作名用简介里的通用名、组次用默认值 **不要编**）；'
        '提不到就说"视频我只能读到标题和简介、看不到画面"再问动作清单，'
        '**绝不虚构视频里没有的动作**；最后一句说明这是按标题/简介推断的',
    '- 抓取失败或内容为空时，直说「这个链接我没读到可用内容」，不要凭标题编内容',
    '- 回执 ok:false 且说「读不到视频正文」时（抖音/小红书这类），直接告诉用户'
        '这个平台读不到正文、请他把视频里的动作名和时长发你；**绝不按标题编动作**',
  ];

  /// 联网搜索规则：**只有 DeepSeek 才有服务端搜索接口**，其它服务商不给
  static const _searchRules = [
    '- 需要最新、有时效性的信息（新闻、价格、赛事、政策、产品发布）时，'
        '先用 web_search 搜，不要凭记忆编',
    '- 要联网就**立刻在这一次回复里调用 web_search**：不要先回「我去搜一下 / '
        '稍等 / 马上给你」这类空承诺——纯文本回复就是本轮最终答复，'
        '用户得再催一次才会真的搜',
    '- 工具返回后**按问题组织成完整答案一次说完**（结论、关键数字、建议都给齐），'
        '不要只罗列搜索结果，也不要停在「搜到了这些」等用户追问',
    '- 引用搜索结果必须标来源：正文结束后单独一行写「来源：站点名 链接」，'
        '最多 3 条；不要用 [标题](url) 这种 Markdown 链接，气泡里不渲染',
    '- 搜索失败或结果为空时，直说「没搜到可靠信息」，不要编造',
  ];

  /// 联网关闭时替代上面四条的唯一一条规则（避免模型以为还能搜）
  static const _webDisabledRule = '- 联网已关闭：无法搜索或抓取网页；'
      '用户需要时，提示他到「教练设定 → 联网」开启';

  /// 构建完整 system prompt（数据为空时也能工作）
  ///
  /// 「角色」段优先用用户自定义文案（`aiPersonaCustom`，trim 后为空视为未设置），
  /// 其余段落（必须遵守 / 输出格式 / 工具使用 / 示例 / 用户数据 / 额外约束）
  /// 一律走原逻辑，**自定义人设不得覆盖安全边界**。
  ///
  /// [memoryLines] 是「教练记得的事」已格式化的行（`伤病·右膝半月板有旧伤`）。
  /// 这里刻意只收 `List<String>` 而不 import `CoachMemory`：
  /// ① builder 不必把 feature 实体倒灌进 core；② 291 行的文件只多 8 行。
  static String build({
    required TrendsData trends,
    UserSettingsEntity? settings,
    List<String> memoryLines = const [],
  }) {
    final style = AiCoachOptions.styleOf(settings?.aiStyle);
    final length = AiCoachOptions.lengthOf(settings?.aiReplyLength);
    final constraints =
        AiCoachOptions.decodeConstraints(settings?.aiConstraints);
    final customPersona = (settings?.aiPersonaCustom ?? '').trim();

    final buf = StringBuffer();
    if (customPersona.isNotEmpty) {
      // 用户自己写的人设：只替换角色段，标题标注来源便于自查
      buf
        ..writeln('# 角色（用户自定义）')
        ..writeln(customPersona)
        ..writeln();
    } else {
      buf
        ..writeln('# 角色')
        ..writeAll(style.personaLines, '\n')
        ..writeln();
    }
    buf
      ..writeln('# 你能做什么（事实，别否认）')
      ..writeln('- 你能直接看图：用户发来的食物照片、体重秤读数、营养成分表、体检单、'
          '聊天截图都能识别；被问"你能识图吗"就回答能，并让他发')
      ..writeln('- 你能读写他的训练与身体数据、建动作和模板、直接打开训练（都要他确认）')
      ..writeln('- 联网搜索与读网页是否可用，见下面「工具使用」段，按那里的说法回答')
      ..writeln()
      ..writeln('# 必须遵守')
      ..writeAll(_rules, '\n')
      ..writeln()
      ..writeln('# 输出格式（有弹性，别套模板）');

    // 风格自带格式口径优先（豆包感：像发微信，1~3 句，不主动分点）
    if (style.outputLines.isNotEmpty) {
      for (final line in style.outputLines) {
        buf.writeln(line);
      }
      buf.writeln('（用户选的档位是「${length.label}」；这个风格下宁短勿长，'
          '别为了凑字数硬编。）');
    } else {
      buf.writeln(length.guide);
      for (final line in _formatGeneric) {
        buf.writeln(line);
      }
    }
    for (final line in _formatBasics) {
      buf.writeln(line);
    }
    buf
      ..writeln()
      ..writeln('# 工具使用（写操作要 action，都要用户确认）')
      ..writeln('- `workout`：log 记训练（补记模板给 template_name，力量动作给 reps、有氧给 minutes）'
          ' / update 改 / delete 删 / start 开练模板；改删前先 query_workouts 拿 id')
      ..writeln('- `body`：weight 记体重 / measurements 记围度 / update_measurement 改围度')
      ..writeln('- `diet`：food 记饮食 —— 用户发食物照片时先按图估食材与分量再记；能估三大营养素'
          '（蛋白/脂肪/碳水）就一起给，估不出留空别填 0；water 记喝水')
      ..writeln('- `settings`：target_weight 目标体重 / diet_target 饮食目标 / profile 身体信息 / reminder 提醒；'
          '查数据用 query_stats / search_food / query_workouts / query_measurements 这些只读工具')
      ..writeln('- `template`：create 建模板（动作名必须与动作库一致，先 query_exercises 确认；'
          '缺失动作会随模板一起建好，不要逐个调用工具）/ delete 删模板（id 来自 query_stats）')
      ..writeln('- `exercise`：create / create_many —— 用户说"帮我加个动作 XX"或库里没有该动作时'
          '先用 exercise:create 加进动作库（分类选力量/有氧/拉伸）；批量加才用 exercise:create_many')
      ..writeln('- `goal`：create / complete / delete（目标 id 先 query_stats 拿，别猜）；'
          '`erase`：records 删某天记录 / all 清空全部（毁灭性，只在用户明说时用，先讲清会留备份）')
      ..writeln('- 调用即执行：不要先说「我去查一下 / 稍等」再等下一轮；没拿到 ok:true 绝不说「已经记好了」；'
          '用户取消确认卡（ok:false）后不再重复请求')
      ..writeln('- 删除 / 修改已有数据是危险操作：先一句话说明后果，等确认卡点头才算数')
      ..writeln('- 不知道有哪些模板时先 query_stats 看 templates，别编名字；用户说"帮我打开模板 / 用 XX 模板开练"'
          '或问"有没有按钮"时不要回答"我没有按钮 / 我做不到"：直接 workout:start 做给他看')
      ..writeln('- 每轮最多 ${AiToolLimits.maxCallsPerRound} 次工具调用，超了拆两步并告知用户');
    // 联网开关：关掉时工具清单里已经没有 web_search / fetch_url，
    // 提示词也必须同步改口，否则模型会一直解释"我搜一下"却调不动。
    // 两个能力分档：读网页任何服务商都有（本地抓取兜底），搜索只有 DeepSeek 有。
    if (settings?.aiWebSearchEnabled ?? true) {
      for (final line in _fetchRules) {
        buf.writeln(line);
      }
      if (aiProviderById(settings?.aiProviderId).id == 'deepseek') {
        for (final line in _searchRules) {
          buf.writeln(line);
        }
      }
    } else {
      buf.writeln(_webDisabledRule);
    }

    buf
      ..writeln('- 已回执 ok:true 的事不要重复执行；用户再提到先确认"要再做一次吗"')
      ..writeln('- 记录类顺手做完就一句话带过，别写成流水账')
      ..writeln()
      ..writeln('# 示例（只学语气和分寸，里面的数字只是示意，'
          '真实数据一律以【用户数据】为准）')
      ..writeAll(kPromptExamples, '\n')
      ..writeln()
      // 陪伴角色一行（C14）：角色是用户选的形象，教练是产品人格；只需名字，形态传 0
      ..writeln(CharacterPromptLine.of(CharacterCatalog.resolve(settings?.characterId, 0)))
      ..writeln()
      ..writeln('# 用户数据（自动注入，真实记录）');

    final data = _dataLines(trends, settings);
    buf.writeAll(data, '\n');
    buf.writeln();
    // 刚上手的新用户：给出引导话术（避免模型对着空数据分析）
    if (!trends.hasWeight && trends.workoutDays == 0) {
      buf
        ..writeln('（用户刚开始使用，暂无体重与训练记录）')
        ..writeln('引导用户：先设置目标体重，记录第一次体重，再开始第一次训练。');
    }

    // 教练记得的事：位置固定在这里 —— 【用户数据】之后、【用户额外约束】之前。
    // 用户手写约束优先级最高（放最后），记忆是被动事实，放它前面。
    // 一条都没有时**整段不出现**（不留空标题）。
    if (memoryLines.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('# 你记得的事（用户以前亲口说过的长期情况，直接用，不要复述给他听）');
      for (final line in memoryLines) {
        buf.writeln('- $line');
      }
    }

    // 用户自定义约束：优先级最高（放最后，模型更容易遵守）
    if (constraints.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('# 用户额外约束（优先级最高，逐条遵守）');
      for (var i = 0; i < constraints.length; i++) {
        buf.writeln('${i + 1}. ${constraints[i]}');
      }
    }
    return buf.toString();
  }

  static List<String> _dataLines(TrendsData t, UserSettingsEntity? settings) {
    final lines = <String>[];
    final now = DateTime.now();
    lines.add('今天：${now.year}-${now.month}-${now.day}');

    if (settings != null) {
      // 昵称注入：改完昵称教练立刻用新名字
      final nickname = settings.nickname?.trim();
      if (nickname != null && nickname.isNotEmpty) lines.add('用户昵称：$nickname');
      final s = <String>[];
      if (settings.heightCm != null) {
        s.add('身高 ${settings.heightCm!.round()}cm');
      }
      if (settings.age != null) s.add('${settings.age}岁');
      if (settings.gender != null) {
        s.add(settings.gender == 'male' ? '男' : '女');
      }
      if (s.isNotEmpty) lines.add(s.join(' · '));
      if (settings.dailyCalorieTarget != null) {
        lines.add('每日热量目标 ${settings.dailyCalorieTarget} 千卡');
      }
    }

    if (t.hasWeight) {
      lines.add('当前体重 ${t.currentJin!.toStringAsFixed(1)} 斤');
      if (t.targetJin != null) {
        lines.add('目标体重 ${t.targetJin!.toStringAsFixed(1)} 斤'
            '（还差 ${(t.remainingJin ?? 0).toStringAsFixed(1)} 斤）');
      }
      if (t.totalLossJin != null) {
        lines.add('累计减重 ${t.totalLossJin!.toStringAsFixed(1)} 斤');
      }
      if (t.weekChangeJin != null) {
        final change = t.weekChangeJin!;
        lines.add('本周体重变化 ${change <= 0 ? '下降' : '上升'}'
            ' ${change.abs().toStringAsFixed(1)} 斤');
      }
    } else {
      lines.add('暂无体重记录');
    }

    if (t.weekWorkoutCount > 0) {
      lines.add('本周训练 ${t.weekWorkoutCount} 次'
          ' / 约 ${t.weekWorkoutMinutes} 分钟');
    } else {
      lines.add('本周还没有训练记录');
    }
    if (t.workoutDays > 0) lines.add('累计训练 ${t.workoutDays} 天');

    if (t.todayCalories != null) {
      lines.add('今日已摄入 ${t.todayCalories!.round()} 千卡');
    }
    if (t.todayCups > 0) lines.add('今日饮水 ${t.todayCups} 杯（约200ml/杯）');

    if (t.daysToTarget != null && t.daysToTarget! > 0) {
      lines.add('按当前趋势预计还需 ${t.daysToTarget} 天达成目标');
    }
    return lines;
  }
}
