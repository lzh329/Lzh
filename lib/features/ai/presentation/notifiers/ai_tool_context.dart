import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 一次对话里的工具上下文（assistant tool_calls + tool 结果），仅内存保存
///
/// 只有拿到 ok:true 的真实结果才会进入这里，模型据此继续回答。
class AiToolContext {
  /// 本轮已执行的工具轮数（防止连环调用）
  int round = 0;

  List<AiMessage> _messages = const [];

  List<AiMessage> get messages => _messages;

  /// 追加一轮「工具调用 + 工具结果」
  void append(AiToolCall call, String result) {
    _messages = [
      ..._messages,
      AiMessage(role: 'assistant', content: '', toolCalls: [call]),
      AiMessage(role: 'tool', content: result, toolCallId: call.id),
    ];
  }

  /// 新的一轮对话 / 重试 / 清空历史时丢弃上下文
  void reset() {
    _messages = const [];
    round = 0;
  }
}
