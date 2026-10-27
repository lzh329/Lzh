import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_side_effects.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

export 'ai_chat_state.dart';

/// 嘎教练对话状态机：流式回复 + 工具回合（写操作必须由用户点头）
class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  /// 最近一次用户输入（失败后供「重试」复用，不重复入库）
  String? _lastUserText;

  /// 当前轮的工具上下文（assistant tool_calls + tool 结果）
  final AiToolContext _tool = AiToolContext();

  late final AiToolExecutor _executor = AiToolExecutor.fromRef(_ref);

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
    if (content.isEmpty || state.isBusy) return;
    if (!state.hasKey) {
      state = state.copyWith(error: '请先点右上角钥匙图标，配置 DeepSeek API Key');
      return;
    }
    _lastUserText = content;
    _tool.reset();
    state = state.copyWith(
      messages: [...state.messages, AiMessage(role: 'user', content: content)],
      clearError: true,
    );
    await _ref.read(aiChatRepoProvider).add('user', content);
    await _request();
  }

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() async {
    if (_lastUserText == null || state.isBusy) return;
    _tool.reset();
    await _request();
  }

  /// 确认执行待确认的写操作
  Future<void> confirmTool() async {
    final preview = state.pendingTool;
    if (preview == null) return;
    state = state.copyWith(clearPendingTool: true, isStreaming: true);
    try {
      final result = await _executor.execute(preview.call);
      _tool.append(preview.call, result);
      applyAiToolSideEffects(_ref, preview.call);
      await _request();
    } on AiToolException catch (e) {
      state = state.copyWith(isStreaming: false, error: '执行失败：${e.message}');
    } catch (e) {
      debugPrint('工具执行异常: $e');
      state = state.copyWith(isStreaming: false, error: '执行失败，请稍后再试');
    }
  }

  /// 取消待确认的写操作（告知模型用户拒绝）
  Future<void> cancelTool() async {
    final preview = state.pendingTool;
    if (preview == null) return;
    state = state.copyWith(clearPendingTool: true, isStreaming: true);
    _tool.append(preview.call, '{"ok":false,"cancelled":"用户取消了这次操作"}');
    await _request();
  }

  /// 发起请求（基于当前历史 + 工具上下文 + 最新 system prompt）
  Future<void> _request() async {
    try {
      final settings = await _ref.read(userSettingsProvider.future);
      final trends = await _ref.read(trendsDataProvider.future);
      final systemPrompt =
          AiPromptBuilder.build(trends: trends, settings: settings);
      state = state.copyWith(
          isStreaming: true, clearStreaming: true, clearError: true);

      final result = await AiService.streamChat(
        apiKey: _resolveKey()!,
        temperature: (settings?.aiTemperature ?? 0.8).clamp(0.3, 1.0),
        tools: AiToolSpecs.defs,
        messages: [
          AiMessage(role: 'system', content: systemPrompt),
          ...state.messages,
          ..._tool.messages,
        ],
        onDelta: (delta) {
          state = state.copyWith(streamingText: state.streamingText + delta);
        },
      );

      if (result.toolCalls.isNotEmpty) {
        await _handleToolCall(result.toolCalls.first);
        return;
      }

      final reply = result.content;
      await _ref.read(aiChatRepoProvider).add('assistant', reply);
      state = state.copyWith(
        messages: [
          ...state.messages,
          AiMessage(role: 'assistant', content: reply)
        ],
        isStreaming: false,
        clearStreaming: true,
      );
      _tool.reset();
    } on AiToolException catch (e) {
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: e.message);
    } on AiServiceException catch (e) {
      debugPrint('AI 对话失败: ${e.message} ${e.body ?? ''}');
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: e.message);
    } catch (e) {
      debugPrint('AI 对话异常: $e');
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: '出错了，请稍后再试');
    }
  }

  /// 处理模型请求的工具调用
  Future<void> _handleToolCall(AiToolCall call) async {
    if (_tool.round >= 2) {
      throw const AiToolException('一次对话里操作次数过多，请分开说');
    }
    _tool.round++;
    // 白名单 + 参数校验（delete_records 要先查库统计条数，故为异步），非法直接抛
    final preview = await _executor.preview(call);
    if (preview.needsConfirm) {
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, pendingTool: preview);
      return;
    }
    // 只读工具：直接执行并把结果回传模型
    final result = await _executor.execute(call);
    _tool.append(call, result);
    await _request();
  }

  /// 保存用户填写的 API Key
  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    await _ref.read(userSettingsRepoProvider).save(aiApiKey: trimmed);
    _ref.invalidate(userSettingsProvider);
    state = state.copyWith(hasKey: AiService.resolveKey(trimmed) != null);
  }

  /// 清空聊天记录（同时丢弃工具上下文）
  Future<void> clearHistory() async {
    await _ref.read(aiChatRepoProvider).clear();
    _tool.reset();
    state = state.copyWith(
        messages: [], clearStreaming: true, clearPendingTool: true);
  }

  /// 错误展示后清空（页面消费）
  void consumeError() {
    state = state.copyWith(clearError: true);
  }

  String? _resolveKey() {
    final settings = _ref.read(userSettingsProvider).valueOrNull;
    return AiService.resolveKey(settings?.aiApiKey);
  }
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
