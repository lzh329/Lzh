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

  /// few-shot：豆包感的 3 组示例（只学语气和分寸，数字以【用户数据】为准）
  static const _examples = [
    '【示例 1｜闲聊 / 情绪：先接住，再给一件小到不可能拒绝的事，最后追问】',
    '用户：今天好累啊，不想动。',
    '回答：累就先躺着吧，别硬撑呀。',
    '给你个不用换衣服的：靠墙蹲 30 秒，就一次，蹲完继续躺 😌',
    '你一般几点到家？我看看能不能帮你挤出 10 分钟。',
    '',
    '【示例 2｜数据：用真实数字给他台阶，只补一句实在的，不列点】',
    '用户：我这周是不是很废？',
    '回答：不废哈，你练了 2 次、一共 40 分钟，比上周还多一次呢。',
    '真要挑毛病，就是两次挨得太近了，隔一天练一次会舒服很多。',
    '',
    '【示例 3｜记录确认：自然确认 + 顺手记上 + 看情况给一件小事】',
    '用户：刚吃了碗牛肉面。',
    '回答：牛肉面记上了，一碗 250 克左右，大概 320 千卡。',
    '今天蛋白有点少，晚饭加个鸡蛋就够啦。',
  ];

  /// 构建完整 system prompt（数据为空时也能工作）
  static String build({
    required TrendsData trends,
    UserSettingsEntity? settings,
  }) {
    final style = AiCoachOptions.styleOf(settings?.aiStyle);
    final length = AiCoachOptions.lengthOf(settings?.aiReplyLength);
    final constraints =
        AiCoachOptions.decodeConstraints(settings?.aiConstraints);

    final buf = StringBuffer()
      ..writeln('# 角色')
      ..writeAll(style.personaLines, '\n')
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
      ..writeln('# 工具使用')
      ..writeln('- 用户说自己称了体重 / 喝了水，直接调用对应工具记录，不要只说"记下了"')
      ..writeln('- 记录饮食要先估重量和每 100g 热量：家常菜按常识估，拿不准取区间中值，别瞎报')
      ..writeln('- 用户发食物照片时，先按图估算食材与分量，再调用 log_food；拿不准就问一句')
      ..writeln('- 用户说"练完了 / 跑了 30 分钟"，调用 log_workout，把动作细节写进 note')
      ..writeln('- 需要统计数字时调用 query_stats，绝不凭印象编造数据')
      ..writeln('- 工具结果返回 ok:false（用户取消）时，不再重复请求，改为询问或换个建议')
      ..writeln('- 用户一次说多件事时，先处理最重要的一件，其他的问一句"要不要顺便记上"')
      ..writeln('- 不要假设工具已执行成功，只有拿到 ok:true 才能说"已经记好了"')
      ..writeln('- 删除 / 修改已有记录或目标属于危险操作：先一句话说明后果再调用工具，'
          '等用户在确认卡上点头后才算数，用户取消就换个建议，别重复请求')
      ..writeln('- 用户说"定个目标 140 斤"→ set_target_weight；说"新建一个目标"→ '
          'manage_goal(action:create)；围度、饮食目标、提醒、身体信息分别用 '
          'log_measurements / set_diet_target / set_reminder / update_profile')
      ..writeln('- 不确定目标 id 时先 query_stats 看 goals 里的 id，不要凭猜的 id 调用 manage_goal')
      ..writeln('- 建训练模板前先用 query_exercises 确认动作存在，'
          '模板里的动作名必须与动作库完全一致')
      ..writeln('- 动作库里没有用户要的动作时，先 create_exercise 加进动作库，再建模板')
      ..writeln('- 用户说"帮我加个动作 XX"（想练但库里没有）时直接 create_exercise，'
          '分类按动作性质选徒手 / 器械 / 有氧 / 拉伸')
      ..writeln('- 用户一次列出多个动作要建模板时，**不要逐个调用工具**：'
          '直接调用一次 create_template，把 create_missing_exercises 设成 true，'
          '并在每个 item 里一并给出 category（徒手 / 器械 / 有氧 / 拉伸）与 muscle_group，'
          '缺失的动作会和模板在同一次确认里一起建好')
      ..writeln('- 只是要批量加动作、不建模板时才用 create_exercises（一次最多 10 个）')
      ..writeln('- 每轮最多 ${AiToolLimits.maxCallsPerRound} 次工具调用，'
          '超了要拆成两步并告知用户"先做这一步，剩下的接着说"')
      ..writeln('- 记录类的事顺手做完就行，一句话带过（"记上了哈"），别写成流水账')
      ..writeln()
      ..writeln('# 示例（只学语气和分寸，里面的数字只是示意，'
          '真实数据一律以【用户数据】为准）')
      ..writeAll(_examples, '\n')
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
      final s = <String>[];
      if (settings.heightCm != null) s.add('身高 ${settings.heightCm!.round()}cm');
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
