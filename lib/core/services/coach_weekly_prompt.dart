import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 周消息的 AI 版提示词（**独立文件，不复用四层结构**）。
///
/// 为什么不塞进 `AiPromptBuilder`：那个 builder 服务的是**多轮对话**
/// （角色 / 边界 / 格式 / 示例四层，目标是"像发微信"）；周消息是**一次性短文**，
/// 目标是"一眼看完且不误读"。两者红线完全不同 —— 混在一起只会让 builder 变成
/// if 分支大杂烩，而它已经 291 行了。
///
/// 三条最容易踩的红线，写在 system 里且可被验收 W-8 证伪：
/// 1. 只许用给定数字，缺数据就不提（不许补 0、不许算平均）；
/// 2. 绝不出现"本周"字样（推的是**上周**的总结，见 PRD 决策 1）；
/// 3. 不承诺减重速度、不提"消耗多少大卡"、不用口号。
class CoachWeeklyPrompt {
  CoachWeeklyPrompt._();

  static List<AiMessage> messages({
    required WeeklyFacts facts,
    required UserSettingsEntity? settings,
  }) =>
      [
        AiMessage(role: 'system', content: systemPrompt(settings: settings)),
        AiMessage(role: 'user', content: userPrompt(facts)),
      ];

  static String systemPrompt({required UserSettingsEntity? settings}) {
    // 复用用户调过的风格语气（他花时间调出来的"豆包感"应该在这里也生效）
    final style = AiCoachOptions.styleOf(settings?.aiStyle);
    final buf = StringBuffer()
      ..writeln('# 角色')
      ..writeAll(style.personaLines, '\n')
      ..writeln()
      ..writeln('# 这次的任务')
      ..writeln('用户会在周一早上收到一条手机通知。你要写这条通知的正文：'
          '一句话总结他**上周**的情况，再给一个**这周能做的小目标**。')
      ..writeln()
      ..writeln('# 必须遵守')
      ..writeln('- 只用【数字】里给出的数字，一个都不许多、不许自己算、不许估算')
      ..writeln('- 【数字】里没给的，整段别提：没给体重就不要提体重，'
          '不提"没变化""持平"这类推断')
      ..writeln('- 绝不出现"本周"两个字，也不要写"这周练了几次"这种数据断言 —— '
          '本周才刚开始，说不了')
      ..writeln('- 不承诺减重速度，不出现"保证""一定能""包瘦""几天就瘦"这类话')
      ..writeln('- 不提"消耗了多少大卡"（估不准，容易被戳破）')
      ..writeln('- 不指责、不追责，不说"你没做到"；0 次训练也要给台阶')
      ..writeln('- 不用 Markdown（#、**、表格），通知里不渲染；要点用"·"开头')
      ..writeln('- 不用 emoji（系统通知里显示成方框的概率很高）')
      ..writeln()
      ..writeln('# 输出要求')
      ..writeln('- 40~120 字，一段话，不要分点、不要换行')
      ..writeln('- 结构：先一句上周的实际进展，再一句这周的小目标')
      ..writeln('- 直接输出正文，不要写"通知：""正文："这类前缀，不要引号')
      ..writeln('- 语气可以暖，但别喊口号；"加油""坚持就是胜利"一律不用');
    return buf.toString();
  }

  static String userPrompt(WeeklyFacts f) {
    final lines = <String>[
      '今天是 ${f.weekStart.year}-${f.weekStart.month}-${f.weekStart.day}（周一）。',
      '统计区间：${_date(f.dataStart)} ~ ${_date(f.dataEnd)}（上周一到上周日）。',
      '',
      '【数字】（这是全部可用数字，没列出的就是不知道）',
      '- 上周训练次数：${f.workoutCount} 次',
      '- 上周训练总时长：${f.workoutMinutes} 分钟',
    ];
    if (f.weighInDays > 0) {
      lines.add('- 上周称重天数：${f.weighInDays} 天');
    }
    if (f.weightChangeKnown) {
      lines.add('- 上周体重：${_jin(f.weightStartJin!)} → ${_jin(f.weightEndJin!)}'
          '（变化 ${_signed(f.weightChangeJin!)}）');
    }
    if (f.totalLossJin != null) {
      lines.add('- 累计减重：${_jin(f.totalLossJin!)}');
    }
    if (f.remainingJin != null) {
      lines.add('- 距目标还差：${_jin(f.remainingJin!)}');
    }
    if (f.nickname != null) {
      lines.add('- 用户昵称：${f.nickname}');
    }
    lines
      ..add('')
      ..add('这周的参考目标（可以照这个意思说，也可以说得更小）：'
          '${f.workoutCount <= 0 ? '先练 1 次，10 分钟也算' : (f.workoutCount <= 2 ? '练 2 次，每次 15 分钟以上' : '保持 3 次')}');
    return lines.join('\n');
  }

  static String _date(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static String _jin(double v) => '${v.toStringAsFixed(1)} 斤';

  static String _signed(double v) =>
      '${v <= 0 ? '下降' : '上升'} ${v.abs().toStringAsFixed(1)} 斤';
}
