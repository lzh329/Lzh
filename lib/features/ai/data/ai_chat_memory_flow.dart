import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/core/services/coach_memory_service.dart';

/// 抽取用到的历史轮数（PRD：「最近 3 轮 user 原话」）
const int kMemoryExtractUserTurns = 3;

/// 从消息流里取最近 [limit] 条 user 原话（时间正序）
///
/// 只取 user：模型的目标是"用户说过什么长期情况"，assistant 的话反而会把
/// 它自己的推断喂回给它（幻觉自我强化）。
List<String> recentUserTurns(List<AiMessage> messages, {int limit = kMemoryExtractUserTurns}) {
  final turns = <String>[];
  for (final m in messages) {
    if (m.role != 'user') continue;
    final text = m.textOnly.trim();
    // 纯图片消息在历史里是「[图片]」占位，没有可引用的话，不进 quote 搜索范围
    if (text.isEmpty || text == '[图片]') continue;
    turns.add(text);
  }
  if (turns.length <= limit) return turns;
  return turns.sublist(turns.length - limit);
}

/// 一轮对话结束后的记忆抽取 —— **fire-and-forget，不 await**。
///
/// 三条规矩（M2 / M12）：
/// 1. 异步、不阻塞回复：对话已经落库并渲染完了才轮到它；
/// 2. 任何异常吞掉只 `debugPrint`：锦上添花不能卡住主流程；
/// 3. 只在**有变化**时补一条灰字留痕，多条合并成 1 条。
Future<void> runMemoryExtraction({
  required CoachMemoryService service,
  required List<String> userTurns,
  required String currentUserText,
  required int? sourceMessageId,
  required Future<void> Function(String text) appendTrace,
}) async {
  try {
    final report = await service.extractAndApply(
      userTurns: userTurns,
      currentUserText: currentUserText,
      sourceMessageId: sourceMessageId,
    );
    if (report == null || report.isEmpty) return;

    const where = '（可在 教练设定 → 教练记得的事 里删）';
    // 纯 forget 的轮次说「已记住」是错的，用户会以为它记了相反的东西
    final remembered = report.added.isNotEmpty || report.updated.isNotEmpty;
    final prefix = remembered ? '🧠 已记住：' : '🧠 已忘掉：';
    await appendTrace('$prefix${report.summary}$where');
  } catch (e) {
    debugPrint('记忆抽取失败（不影响对话）: $e');
  }
}
