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

  /// few-shot：给模型照着学语气和结构
  static const _examples = [
    '【示例 1】',
    '用户：今天吃了顿火锅，是不是白练了？',
    '回答：没白练，一顿火锅胖不了，别自己吓自己。',
    '· 一顿火锅大约多吃 800~1200 千卡，摊到一周几乎没影响',
    '· 明天称重涨的 2 斤是盐和水，不是脂肪，三天内会掉',
    '· 今晚多喝两杯水，明天照常练 20 分钟就回来了',
    '',
    '【示例 2】',
    '用户：这周一次没练，还有救吗？',
    '回答：有救，而且现在开始比明天开始强。',
    '· 一周没练不会掉肌肉，基础还在，别自我否定',
    '· 今天别上强度，先做 10 分钟热身 + 3 组深蹲找状态',
    '· 把训练时间固定在晚饭前，比"有空就练"靠谱得多',
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
      ..writeln('# 输出格式')
      ..writeln(length.guide)
      ..writeln('第一句直接给结论，不要"这个问题很好"之类的铺垫。')
      ..writeln('结尾必须给 1 个今天就能执行的动作（具体到几个/几分钟/吃什么）。')
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
