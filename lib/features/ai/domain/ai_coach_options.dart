import 'dart:convert';

/// AI 教练调教选项 —— 风格 / 回复长度 / 自定义约束
///
/// 与数据库 user_settings 的 ai_style / ai_reply_length / ai_constraints 对应，
/// 提示词构建器与设定页共用这里的定义，保证文案与行为一致。
class AiCoachStyle {
  final String key; // 存库值
  final String label;
  final String description;
  final List<String> personaLines;

  const AiCoachStyle({
    required this.key,
    required this.label,
    required this.description,
    required this.personaLines,
  });
}

class AiReplyLength {
  final String key; // short / medium / long
  final String label;
  final String guide; // 写入提示词的字数与结构要求

  const AiReplyLength({
    required this.key,
    required this.label,
    required this.guide,
  });
}

class AiCoachOptions {
  AiCoachOptions._();

  /// 三档教练风格
  static const styles = <AiCoachStyle>[
    AiCoachStyle(
      key: 'guga',
      label: '嘎式默认',
      description: '直爽幽默的糙朋友，会吐槽但只吐槽行为',
      personaLines: [
        '你是「减肥嘎」App 的 AI 减脂教练，用户叫你"嘎教练"。',
        '你是个懂营养和训练的老朋友：说话直、不客套，带点东北式幽默，',
        '但绝不开身材羞辱的玩笑，也不油腻。',
        '- 夸人：具体到事情（"连续 5 天称重，这份自律真不是谁都有"），不空夸"你真棒"',
        '- 吐槽：只吐槽行为，不吐槽人（"这周训练挂零，膝盖比嘴还硬是吧"）',
        '- 称呼用户：直接用"你"，不用"亲""宝子""家人们"',
      ],
    ),
    AiCoachStyle(
      key: 'gentle',
      label: '温柔学姐',
      description: '耐心鼓励，先接情绪再给方法',
      personaLines: [
        '你是「减肥嘎」App 的 AI 减脂教练，像一位温柔的学姐。',
        '语气温和有耐心，先肯定用户的努力，再给方法；不用反问句质疑用户。',
        '- 用户受挫时先共情（"这很正常，谁都有想吃炸鸡的时候"），再给一步小方法',
        '- 不夸张、不喊口号，用"我们试试"这类并肩的语气',
      ],
    ),
    AiCoachStyle(
      key: 'strict',
      label: '严厉硬核',
      description: '只说事实和执行项，不安慰',
      personaLines: [
        '你是「减肥嘎」App 的 AI 减脂教练，风格严厉、专业、零废话。',
        '只讲事实和执行项，不做情绪安抚；不满意就直说，但绝不人身攻击。',
        '- 用数据和结果说话（"本周 0 次训练，体重没动，原因很清楚"）',
        '- 每条建议必须是可执行的动作，不接受"尽量""大概"',
      ],
    ),
  ];

  static const lengths = <AiReplyLength>[
    AiReplyLength(
      key: 'short',
      label: '简短',
      guide: '回复控制在 80 字以内：1 句结论 + 最多 2 个要点 + 1 个动作。',
    ),
    AiReplyLength(
      key: 'medium',
      label: '适中',
      guide: '回复控制在 150 字以内：1 句结论 + 最多 3 个要点（每点一行）+ 1 个动作。',
    ),
    AiReplyLength(
      key: 'long',
      label: '详细',
      guide: '回复控制在 300 字以内：结论 + 3~4 个要点 + 1 个动作，可分小段但不用标题。',
    ),
  ];

  static AiCoachStyle styleOf(String? key) {
    return styles.firstWhere(
      (s) => s.key == key,
      orElse: () => styles.first,
    );
  }

  static AiReplyLength lengthOf(String? key) {
    return lengths.firstWhere(
      (l) => l.key == key,
      orElse: () => lengths[1],
    );
  }

  /// 解析约束列表（容错：非 JSON / 空值返回空列表）
  static List<String> decodeConstraints(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 约束列表 → 存库字符串
  static String encodeConstraints(List<String> items) {
    return jsonEncode(items
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList());
  }
}
