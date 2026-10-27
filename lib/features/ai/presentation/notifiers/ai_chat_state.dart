import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart'
    show ExerciseSlot;

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

  /// 待启动的训练（start_workout 确认后的槽位）；null = 没有要跳转的训练
  ///
  /// 由页面消费：看到非空就跳训练页，跳完调 `consumeWorkoutStart()` 清空，
  /// 避免从训练页返回聊天页时又跳一次。
  final List<ExerciseSlot>? pendingWorkoutStart;

  /// 待启动训练的模板名（跳转后 SnackBar 文案用）
  final String? pendingWorkoutTemplateName;

  const AiChatState({
    this.messages = const [],
    this.streamingText = '',
    this.isStreaming = false,
    this.hasKey = false,
    this.error,
    this.pendingTool,
    this.pendingWorkoutStart,
    this.pendingWorkoutTemplateName,
  });

  bool get isBusy => isStreaming || pendingTool != null;

  /// 是否有待跳转的训练
  bool get hasPendingWorkoutStart =>
      pendingWorkoutStart != null && pendingWorkoutStart!.isNotEmpty;

  AiChatState copyWith({
    List<AiMessage>? messages,
    String? streamingText,
    bool? isStreaming,
    bool? hasKey,
    String? error,
    AiToolPreview? pendingTool,
    List<ExerciseSlot>? pendingWorkoutStart,
    String? pendingWorkoutTemplateName,
    bool clearError = false,
    bool clearStreaming = false,
    bool clearPendingTool = false,
    bool clearPendingWorkout = false,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      streamingText:
          clearStreaming ? '' : (streamingText ?? this.streamingText),
      isStreaming: isStreaming ?? this.isStreaming,
      hasKey: hasKey ?? this.hasKey,
      error: clearError ? null : (error ?? this.error),
      pendingTool: clearPendingTool ? null : (pendingTool ?? this.pendingTool),
      pendingWorkoutStart: clearPendingWorkout
          ? null
          : (pendingWorkoutStart ?? this.pendingWorkoutStart),
      pendingWorkoutTemplateName: clearPendingWorkout
          ? null
          : (pendingWorkoutTemplateName ?? this.pendingWorkoutTemplateName),
    );
  }
}
