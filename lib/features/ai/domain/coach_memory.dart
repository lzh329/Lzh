/// 记忆的 5 类白名单 —— **唯一事实来源**。
///
/// 与 PRD M3 逐字一致；改这里必须同步改 `CoachMemoryPrompt` 的白名单文案、
/// `CoachMemoryPolicy` 的每类上限与验收 M-3。三类地方分开写必然漂。
const Set<String> kMemoryCategories = <String>{
  'injury', // 伤病 / 疼痛 / 旧伤 / 手术史
  'diet', // 忌口 / 过敏 / 不吃 / 只能吃
  'schedule', // 作息 / 固定时间
  'agreement', // 约定 / 承诺
  'preference', // 偏好 / 讨厌
};

/// 记忆类目的展示名（记忆页分组标题、注入 prompt 的行前缀共用）
const Map<String, String> kMemoryCategoryLabels = <String, String>{
  'injury': '伤病',
  'diet': '忌口',
  'schedule': '作息',
  'agreement': '约定',
  'preference': '偏好',
};

/// 一条记忆（用户亲口说过的长期情况）。
///
/// [quote] 是**用户原话片段**，不是模型的转述 —— 它是这条记忆的出生证明，
/// 也是防腐层的落点：本地校验必须是当轮用户原话的子串，否则丢弃。
class CoachMemory {
  final int id;
  final String category;
  final String topic;
  final String content;
  final String quote;
  final int? sourceMessageId;
  final DateTime createdAt;

  /// 覆盖时更新；记忆页展示的是这个时间（"这条最近一次被确认的时间"）
  final DateTime updatedAt;

  /// 最近一次被注入进 prompt 的时间（null = 从没被用过）
  ///
  /// 淘汰依据：`last_used_at` 最早的那条先淘汰 —— "最近没用到"比"最早的先删"
  /// 更符合直觉。
  final DateTime? lastUsedAt;

  const CoachMemory({
    required this.id,
    required this.category,
    required this.topic,
    required this.content,
    required this.quote,
    required this.createdAt,
    required this.updatedAt,
    this.sourceMessageId,
    this.lastUsedAt,
  });

  /// 注入进 prompt 的一行：只用 `类目·内容`，**不带 quote**
  /// （防 prompt 膨胀，也防原话里的细节外泄 —— PRD M11）
  String get promptLine =>
      '${kMemoryCategoryLabels[category] ?? category}·$content';

  String get categoryLabel => kMemoryCategoryLabels[category] ?? category;

  CoachMemory copyWith({DateTime? lastUsedAt, DateTime? updatedAt}) {
    return CoachMemory(
      id: id,
      category: category,
      topic: topic,
      content: content,
      quote: quote,
      sourceMessageId: sourceMessageId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}

/// 抽取器产出的一条候选（尚未过校验闸门）。
///
/// 刻意与 [CoachMemory] 分开：候选是"模型说它听到了什么"，实体是"已经过三道
/// 校验、可以给用户看的东西"。合并成一个类型等于让未校验的数据拿到 id。
class CoachMemoryCandidate {
  /// remember / forget（forget = 用户改口，删掉该 (category, topic)）
  final String action;
  final String category;
  final String topic;
  final String content;
  final String quote;
  final double confidence;

  const CoachMemoryCandidate({
    required this.action,
    required this.category,
    required this.topic,
    required this.content,
    required this.quote,
    this.confidence = 1.0,
  });

  bool get isForget => action == 'forget';
}
