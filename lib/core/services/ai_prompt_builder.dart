import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// AI 教练 system prompt 构建器
///
/// 把用户本地数据（体重趋势 / 训练频率 / 目标进度 / 饮食饮水）
/// 组装进 system prompt，让模型成为「懂用户数据的私人教练」。
class AiPromptBuilder {
  AiPromptBuilder._();

  static const _personaLines = [
    '你是「减肥嘎」App 里的 AI 减脂教练，用户昵称你为"嘎教练"。',
    '你的建议基于用户的真实数据（见下方），回答务必：',
    '1. 简短直接，先给结论再给理由，口语化，像朋友聊天；',
    '2. 给可执行的具体建议（具体到动作、时长、餐食），不说空话；',
    '3. 语气积极幽默，用户坚持得好要真诚夸奖，偷懒了用轻松的"嘎式吐槽"督促；',
    '4. 涉及医疗/伤病问题提醒用户咨询医生，不诊断；',
    '5. 用户问与减脂训练完全无关的话题时，礼貌拉回健身话题。',
  ];

  /// 构建完整 system prompt（数据为空时也能工作）
  static String build({
    required TrendsData trends,
    UserSettingsEntity? settings,
  }) {
    final buf = StringBuffer()
      ..writeAll(_personaLines, '\n')
      ..writeln()
      ..writeln('── 用户当前数据（自动注入，真实记录）──');
    final data = _dataLines(trends, settings);
    buf.writeAll(data, '\n');
    // 刚上手的新用户：给出引导话术（避免模型对着空数据分析）
    if (!trends.hasWeight && trends.workoutDays == 0) {
      buf
        ..writeln('（用户刚开始使用，暂无体重与训练记录）')
        ..writeln('引导用户：先设置目标体重，记录第一次体重，再开始第一次训练。');
    }
    return buf.toString();
  }

  static List<String> _dataLines(
      TrendsData t, UserSettingsEntity? settings) {
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
