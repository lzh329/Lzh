import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// AI 聊天页状态
class AiChatState {
  /// 历史消息（含已完成的 user / assistant）
  final List<AiMessage> messages;

  /// 流式中的部分回复（打字机效果）
  final String streamingText;

  final bool isStreaming;

  /// API Key 是否已配置（dart-define 或设置里）
  final bool hasKey;

  /// 最近一次错误（展示后清空）
  final String? error;

  /// 等待用户确认的工具调用（写操作闸门）
  final AiToolPreview? pendingTool;

  const AiChatState({
    this.messages = const [],
    this.streamingText = '',
    this.isStreaming = false,
    this.hasKey = false,
    this.error,
    this.pendingTool,
  });

  bool get isBusy => isStreaming || pendingTool != null;

  AiChatState copyWith({
    List<AiMessage>? messages,
    String? streamingText,
    bool? isStreaming,
    bool? hasKey,
    String? error,
    AiToolPreview? pendingTool,
    bool clearError = false,
    bool clearStreaming = false,
    bool clearPendingTool = false,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      streamingText:
          clearStreaming ? '' : (streamingText ?? this.streamingText),
      isStreaming: isStreaming ?? this.isStreaming,
      hasKey: hasKey ?? this.hasKey,
      error: clearError ? null : (error ?? this.error),
      pendingTool: clearPendingTool ? null : (pendingTool ?? this.pendingTool),
    );
  }
}
