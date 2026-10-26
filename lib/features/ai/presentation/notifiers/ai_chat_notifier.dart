import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

// ───────────────────── 状态 ─────────────────────

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

  const AiChatState({
    this.messages = const [],
    this.streamingText = '',
    this.isStreaming = false,
    this.hasKey = false,
    this.error,
  });

  AiChatState copyWith({
    List<AiMessage>? messages,
    String? streamingText,
    bool? isStreaming,
    bool? hasKey,
    String? error,
    bool clearError = false,
    bool clearStreaming = false,
  }) {
    return AiChatState(
      messages: messages ?? this.messages,
      streamingText:
          clearStreaming ? '' : (streamingText ?? this.streamingText),
      isStreaming: isStreaming ?? this.isStreaming,
      hasKey: hasKey ?? this.hasKey,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ───────────────────── Notifier ─────────────────────

class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  /// 最近一次用户输入（失败后供「重试」复用，不重复入库）
  String? _lastUserText;

  AiChatNotifier(this._ref) : super(const AiChatState()) {
    _init();
  }

  Future<void> _init() async {
    final settings = await _ref.read(userSettingsProvider.future);
    final key = AiService.resolveKey(settings?.aiApiKey);
    final history = await _ref.read(aiChatRepoProvider).getHistory();
    state = state.copyWith(messages: history, hasKey: key != null);
  }

  /// 发送一条消息（流式接收回复）
  Future<void> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || state.isStreaming) return;
    if (!state.hasKey) {
      state = state.copyWith(
          error: '请先点右上角钥匙图标，配置 DeepSeek API Key');
      return;
    }
    _lastUserText = content;
    final messages = [...state.messages, AiMessage(role: 'user', content: content)];
    state = state.copyWith(messages: messages, clearError: true);
    await _ref.read(aiChatRepoProvider).add('user', content);
    await _request();
  }

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() async {
    if (_lastUserText == null || state.isStreaming) return;
    await _request();
  }

  /// 发起请求（基于当前历史 + 最新 system prompt）
  Future<void> _request() async {
    try {
      final systemPrompt = await _buildSystemPrompt();
      state = state.copyWith(
          isStreaming: true, clearStreaming: true, clearError: true);
      final apiKey = _resolveKey()!;
      final reply = await AiService.streamChat(
        apiKey: apiKey,
        messages: [
          AiMessage(role: 'system', content: systemPrompt),
          ...state.messages,
        ],
        onDelta: (delta) {
          state = state.copyWith(streamingText: state.streamingText + delta);
        },
      );
      await _ref.read(aiChatRepoProvider).add('assistant', reply);
      state = state.copyWith(
        messages: [...state.messages, AiMessage(role: 'assistant', content: reply)],
        isStreaming: false,
        clearStreaming: true,
      );
    } on AiServiceException catch (e) {
      debugPrint('AI 对话失败: ${e.message} ${e.body ?? ''}');
      state = state.copyWith(isStreaming: false, clearStreaming: true, error: e.message);
    } catch (e) {
      debugPrint('AI 对话异常: $e');
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: '出错了，请稍后再试');
    }
  }

  /// 保存用户填写的 API Key
  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    await _ref.read(userSettingsRepoProvider).save(aiApiKey: trimmed);
    _ref.invalidate(userSettingsProvider);
    state = state.copyWith(hasKey: AiService.resolveKey(trimmed) != null);
  }

  /// 清空聊天记录
  Future<void> clearHistory() async {
    await _ref.read(aiChatRepoProvider).clear();
    state = state.copyWith(messages: [], clearStreaming: true);
  }

  /// 错误展示后清空（页面消费）
  void consumeError() {
    state = state.copyWith(clearError: true);
  }

  String? _resolveKey() {
    final settings = _ref.read(userSettingsProvider).valueOrNull;
    return AiService.resolveKey(settings?.aiApiKey);
  }

  Future<String> _buildSystemPrompt() async {
    final trends = await _ref.read(trendsDataProvider.future);
    final settings = await _ref.read(userSettingsProvider.future);
    return AiPromptBuilder.build(trends: trends, settings: settings);
  }
}

final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
