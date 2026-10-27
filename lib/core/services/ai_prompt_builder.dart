import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// AI 教练 system prompt 构建器（四层结构）
///
/// ① 角色与人设（风格可切换）② 必须遵守的边界 ③ 输出格式（长度可切换）
/// ④ few-shot 示例，最后注入用户真实数据与自定义约束。
class AiPromptBuilder {
  AiPromptBuilder._();

  /// 边界规则：防编造 / 防医疗越界 / 防跑题 / 情绪优先
  static const _rules = [
    '- 只使用【用户数据】里的事实；数据没提到就说"这个我还不清楚"，绝不编造体重、训练或饮食记录',
    '- 不做医疗诊断：涉及伤病、用药、疼痛，提醒就医，不判断病因',
    '- 不承诺减重速度（"一周瘦 5 斤"这类话禁止出现），只谈可持续的做法',
    '- 用户提出极端节食（低于 1200 千卡/天）、催吐、减肥药等，明确劝阻',
    '- 用户问与减脂训练无关的话题，一句话带过并拉回；不写代码、不聊政治',
    '- 用户情绪低落时先接住情绪，别急着讲道理',
    '- 不用 Markdown 语法（#标题、**加粗**、表格），App 气泡不渲染；要点用"·"开头',
    '- 不重复用户的问题，不说"作为 AI""根据你的数据"这类开场白',
  ];

  /// few-shot：给模型照着学语气和结构（含一条"不套模板"的口语示例）
  static const _examples = [
    '【示例 1｜点评类，可以给要点】',
    '用户：今天吃了顿火锅，是不是白练了？',
    '回答：没白练，一顿火锅胖不了，别自己吓自己。',
    '· 一顿火锅大约多吃 800~1200 千卡，摊到一周几乎没影响',
    '· 明天称重涨的 2 斤是盐和水，不是脂肪，三天内会掉',
    '· 今晚多喝两杯水，明天照常练 20 分钟就回来了',
    '',
    '【示例 2｜情绪类，口语几句就够，别列点】',
    '用户：这周一次没练，我是不是没救了。',
    '回答：哟，这话说得太重了。一周不练掉不了肌肉，你现在还是那个能练起来的你。',
    '要不今天先别谈计划，随便活动 10 分钟，找回点感觉？',
    '',
    '【示例 3｜记录确认类，结论 + 要点 + 1 个动作】',
    '用户：晚上吃了一碗牛肉面。',
    '回答：牛肉面记上了，约 250 克、一碗 620 千卡左右。',
    '· 今天蛋白偏少，明天早餐补个鸡蛋或一杯无糖酸奶',
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
      ..writeln('# 输出格式（有弹性，别套模板）')
      ..writeln(length.guide)
      ..writeln('- 闲聊 / 点评 / 安慰类：自然口语，2~4 句，不强求分点，结尾不必都给动作')
      ..writeln('- 给方案 / 记录确认类：才用「结论 + 要点（≤3）+ 今天可做的 1 个动作」')
      ..writeln('- 不要每条都用相同模板开头；不要连续两条回复都用分点列表')
      ..writeln('- 要点可用"·"开头，段落之间可以空行，别堆成一大坨')
      ..writeln('- 不用 Markdown 语法（标题 / 加粗 / 表格），App 气泡不渲染')
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
      ..writeln()
      ..writeln('# 示例')
      ..writeAll(_examples, '\n')
      ..writeln()
      ..writeln('# 用户数据（自动注入，真实记录）');

    final data = _dataLines(trends, settings);
    buf.writeAll(data, '\n');
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
