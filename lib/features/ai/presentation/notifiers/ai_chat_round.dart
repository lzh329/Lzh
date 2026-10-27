import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 一次对话回合的结果（正文 / 工具调用 / 给用户看的错误文案）
class AiChatRoundResult {
  final String content;
  final List<AiToolCall> toolCalls;
  final String? error;

  const AiChatRoundResult({
    this.content = '',
    this.toolCalls = const [],
    this.error,
  });

  const AiChatRoundResult.failure(String this.error)
      : content = '',
        toolCalls = const [];

  bool get isFailed => error != null;

  /// 跑一轮流式请求；网络 / 服务端异常统一转成可读文案（不向外抛）
  ///
  /// 工具调用异常（[AiToolException]）由调用方自己处理，这里原样抛出。
  /// [webEnabled] 关闭时只下发 17 个工具（不含 web_search / fetch_url）。
  static Future<AiChatRoundResult> run({
    required String apiKey,
    required List<AiMessage> messages,
    required void Function(String delta) onDelta,
    double temperature = AiService.defaultTemperature,
    bool webEnabled = true,
  }) async {
    try {
      final res = await AiService.streamChat(
        apiKey: apiKey,
        messages: messages,
        onDelta: onDelta,
        tools: AiToolSpecs.defsFor(webEnabled: webEnabled),
        temperature: temperature,
      );
      return AiChatRoundResult(
        content: res.content,
        toolCalls: res.toolCalls,
      );
    } on AiServiceException catch (e) {
      debugPrint('AI 对话失败: ${e.message} 响应体: ${e.body ?? ''}');
      return AiChatRoundResult.failure(e.message);
    } catch (e) {
      debugPrint('AI 对话异常: $e');
      return const AiChatRoundResult.failure('出错了，请稍后再试');
    }
  }
}
