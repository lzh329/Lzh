import 'package:fittrack/core/services/ai_service.dart' show AiMessage;

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
