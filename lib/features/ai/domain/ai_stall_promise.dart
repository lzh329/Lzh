import 'package:fittrack/features/ai/data/ai_service.dart' show AiMessage;

/// 检测模型是否回了一句「空承诺」——嘴上说要去搜/查/看，但这一轮
/// **没有带任何工具调用**，于是纯文本就成了最终答复，用户得再催一次。
///
/// 背景（2026-10-30 真机）：用户让嘎教练「搜点东西」，模型回「我去搜一下」
/// 就停住，等用户再问一句才真的调用 web_search。提示词的软约束拦不住这种
/// 模型自主行为，必须在状态机层面兜底。
///
/// 判据：文本很短（≤ 24 字）且命中"去搜/去查/去看看/稍等/马上"这类承诺词，
/// 同时没有 tool_calls。命中就拦截，由调用方补发一轮"现在就搜"。
bool isStallPromise(String content, List<AiMessage>? /* unused */ _) {
  final t = content.trim();
  if (t.isEmpty || t.length > 24) return false;

  const marks = <String>[
    '我去搜',
    '去搜一下',
    '帮你搜',
    '我去查',
    '去查一下',
    '帮你查',
    '去看看',
    '我去看',
    '马上给你',
    '马上搜',
    '稍等',
    '等我一下',
    '让我找',
    '我来找',
  ];
  for (final m in marks) {
    if (t.contains(m)) return true;
  }
  return false;
}

/// 检测模型是否**凭空断言操作已完成**（本轮没有任何工具调用）
///
/// 背景（真机）：用户让教练「补 11 月 2 日的训练记录」，模型直接回
/// 「已帮你补记好了」—— 全程没有 tool_calls，也没弹确认卡，数据根本没写。
/// 空承诺（[isStallPromise]）拦的是"我去做"，这条拦的是"我做完了"，更危险：
/// 用户会以为已经记上了，几天后才发现是空的。
///
/// 判据：命中完成态断言 **且** 没有任何条件/征询词（"如果/要不要/可以帮你"
/// 这类是在提问，不是在宣称完成）。
bool claimsCompletedAction(String content) {
  final t = content.trim();
  if (t.isEmpty) return false;

  // 条件 / 征询语气 → 不算断言完成
  const hedges = <String>[
    '如果',
    '要不要',
    '可以帮你',
    '我可以',
    '需要我',
    '是否',
    '吗？',
    '吗?',
    '确认',
  ];
  for (final h in hedges) {
    if (t.contains(h)) return false;
  }

  const claims = <String>[
    '已记录',
    '已帮你记',
    '已帮你补记',
    '已补记',
    '已补上',
    '记好了',
    '已经记好',
    '已添加',
    '已创建',
    '已删除',
    '已修改',
    '已更新',
    '已设好',
    '已设置',
  ];
  for (final c in claims) {
    if (t.contains(c)) return true;
  }
  return false;
}

/// 用户这句话是不是在要求「写数据」的动作（记录/添加/删除/修改/设置…）
///
/// 为什么不靠模型的措辞判定：固定词表（"已记录/已补记/记好了"）会被模型
/// 换个说法绕过（"已经给你加到记录里啦"、"补上了哈"、"弄好了"）。
/// 反过来看**用户意图**才稳：用户要写、本轮却没有工具调用 → 一定没做。
bool looksLikeWriteRequest(String userText) {
  final t = userText.trim();
  if (t.isEmpty) return false;

  // 纯提问/推荐类先排除：这些不是写操作
  const readOnlyHints = <String>['几次', '多少个', '多少斤', '推荐', '怎么', '为什么'];
  final looksQuestion = t.endsWith('？') || t.endsWith('?');
  if (looksQuestion) return false;
  for (final h in readOnlyHints) {
    if (t.contains(h)) return false;
  }

  const roots = <String>[
    '记录',
    '记一下',
    '记一笔',
    '补记',
    '补上',
    '添加',
    '加个',
    '增加',
    '新建',
    '建个',
    '创建',
    '删除',
    '删掉',
    '删了',
    '去掉',
    '修改',
    '改成',
    '换成',
    '更新',
    '设置',
    '设个',
    '设成',
    '调整',
  ];
  for (final r in roots) {
    if (t.contains(r)) return true;
  }
  return false;
}

/// 模型是否在「诚实失败」（明确说做不到 / 找不到）
///
/// 这种情况**不该**补发：它已经按规则 (b) 回答了，再逼一轮只会得到重复话术。
bool isHonestFailure(String content) {
  const marks = <String>['没法', '不能', '失败', '找不到', '没找到', '需要先', '请先', '你得'];
  for (final m in marks) {
    if (content.contains(m)) return true;
  }
  return false;
}

/// 是否需要对这一轮「无工具调用的纯文本」补发一轮
///
/// 判定放在 domain：notifier 只负责调用与状态，不堆规则。
/// - 本轮没有任何工具调用
/// - 本轮还没补发过（独立计数，最多 1 次，防死循环）
/// - 用户是在要求写操作 **或** 模型自己声称已完成
/// - 且模型不是在诚实失败
bool needWriteIntentNudge({
  required String userText,
  required String content,
  required bool hasToolCalls,
  required bool alreadyNudged,
}) {
  if (hasToolCalls || alreadyNudged) return false;
  if (isHonestFailure(content)) return false;
  return looksLikeWriteRequest(userText) || claimsCompletedAction(content);
}
