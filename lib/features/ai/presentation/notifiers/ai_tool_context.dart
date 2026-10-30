import 'dart:convert';

import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 一次对话里的工具上下文（assistant tool_calls + tool 结果），仅内存保存
///
/// 真实结果（ok:true）与**失败回执**（ok:false）都会进入这里，模型据此继续
/// 回答。失败必须回执：工具失败如果只变成一个 toast，模型完全不知情，下一轮
/// 就会凭空说"已经建好了"——用户在模板页却什么也找不到（2026-10-28 真实事故：
/// AI 声称建好模板，模板页没有）。
class AiToolContext {
  /// 本轮已执行的工具轮数（防止连环调用）
  int round = 0;

  List<AiMessage> _messages = const [];

  List<AiMessage> get messages => _messages;

  /// 失败回执的标准形状：模型看到 ok:false + 原因，才会纠正而不是幻觉成功
  static String failureReceipt(String message) =>
      jsonEncode({'ok': false, 'error': message});

  /// 追加一轮「工具调用 + 工具结果」
  ///
  /// assistant 那一轮的 content 留空，[AiMessage.toJson] 会把它序列化成 null
  /// （DeepSeek 对带 tool_calls 的消息要求 content 为 null）；
  /// tool 结果带上 [AiMessage.toolName]，否则模型无法把结果和工具对上。
  void append(AiToolCall call, String result) {
    _messages = [
      ..._messages,
      AiMessage(role: 'assistant', content: '', toolCalls: [call]),
      AiMessage(
        role: 'tool',
        content: result,
        toolCallId: call.id,
        toolName: call.name,
      ),
    ];
  }

  /// 追加一条 system 内部指令（不改变对话可见内容，只给模型下一轮的行为加约束）。
  ///
  /// 用于「空承诺兜底」：模型回了「我去搜一下」却没调工具时，补发一条
  /// 指令让它立刻执行搜索。system 消息不走 tool 协议，不会破坏
  /// DeepSeek 对 tool 消息必须配对 assistant tool_calls 的约束。
  void appendSystem(String content) {
    _messages = [
      ..._messages,
      AiMessage(role: 'system', content: content),
    ];
  }

  /// 新的一轮对话 / 重试 / 清空历史时丢弃上下文
  void reset() {
    _messages = const [];
    round = 0;
  }
}
