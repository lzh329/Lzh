import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_side_effects.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

export 'ai_chat_state.dart';

/// 嘎教练对话状态机：流式回复 + 工具回合（写操作必须由用户点头）
class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  /// 最近一次用户消息内容（失败后供「重试」复用，不重复入库；图片消息也能重试）
  Object? _lastUserContent;

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

  /// 发送一条消息（[image] 不为空时走视觉消息，文本可留空）
  Future<void> send(String text, {File? image}) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && image == null) || state.isBusy) return;
    if (!state.hasKey) {
      state = state.copyWith(error: '请先点右上角钥匙图标，配置 DeepSeek API Key');
      return;
    }
    final prepared =
        await AiUserPayloadResult.load(text: trimmed, image: image);
    final payload = prepared.payload;
    if (payload == null) {
      state = state.copyWith(error: prepared.error);
      return;
    }
    _lastUserContent = payload.content;
    _tool.reset();
    state = state.copyWith(
      messages: [
        ...state.messages,
        AiMessage(role: 'user', content: payload.content),
      ],
      clearError: true,
    );
    // 数据库只存文本，图片用「[图片]」占位
    await _ref.read(aiChatRepoProvider).add('user', payload.historyText);
    await _request();
  }

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() async {
    if (_lastUserContent == null || state.isBusy) return;
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
  ///
  /// 全流程都在 try 内（含取设置 / 取趋势）：任何一步抛异常都必须把
  /// [AiChatState.isStreaming] 复位，否则输入框会被永久禁用、只能重启 App。
  Future<void> _request() async {
    try {
      // 取设置与趋势数据失败也要兜住，不能把异常冒泡到 send()
      final settings = await _ref.read(userSettingsProvider.future);
      final trends = await _ref.read(trendsDataProvider.future);
      // 联网开关：没设置过（老库 / 首启）一律按开启处理
      final webEnabled = settings?.aiWebSearchEnabled ?? true;
      state = state.copyWith(
          isStreaming: true, clearStreaming: true, clearError: true);

      final round = await AiChatRoundResult.run(
        apiKey: AiService.resolveKey(settings?.aiApiKey) ?? '',
        temperature: (settings?.aiTemperature ?? AiService.defaultTemperature)
            .clamp(0.3, 1.0),
        webEnabled: webEnabled,
        messages: [
          AiMessage(
            role: 'system',
            content: AiPromptBuilder.build(trends: trends, settings: settings),
          ),
          ...state.messages,
          ..._tool.messages,
        ],
        onDelta: (delta) {
          state = state.copyWith(streamingText: state.streamingText + delta);
        },
      );

      if (round.isFailed) {
        state = state.copyWith(
            isStreaming: false, clearStreaming: true, error: round.error);
        return;
      }
      if (round.toolCalls.isNotEmpty) {
        await _handleToolCall(round.toolCalls.first);
        return;
      }
      await _ref.read(aiChatRepoProvider).add('assistant', round.content);
      state = state.copyWith(
        messages: [
          ...state.messages,
          AiMessage(role: 'assistant', content: round.content)
        ],
        isStreaming: false,
        clearStreaming: true,
      );
      _tool.reset();
    } on AiToolException catch (e) {
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: e.message);
    } catch (e) {
      // 兜底：写库 / 取设置等非工具异常（如 Drift 报错）也要复位状态
      debugPrint('AI 对话异常: $e');
      state = state.copyWith(
          isStreaming: false, clearStreaming: true, error: '出错了，请稍后再试');
    }
  }

  /// 处理模型请求的工具调用（次数上限只防死循环，写操作仍逐次确认）
  Future<void> _handleToolCall(AiToolCall call) async {
    if (_tool.round >= AiToolLimits.maxCallsPerRound) {
      throw const AiToolException(AiToolLimits.overLimitMessage);
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
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
