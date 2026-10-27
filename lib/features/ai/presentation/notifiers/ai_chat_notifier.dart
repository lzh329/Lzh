import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/ai_workout_intent.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_session.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_side_effects.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

export 'ai_chat_state.dart';

/// 嘎教练对话状态机：流式回复 + 工具回合（写操作必须由用户点头）
///
/// 会话事务（发送 / 重试 / 历史 / Key）在 [AiChatSession]。
class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  /// 当前轮的工具上下文（assistant tool_calls + tool 结果）
  final AiToolContext _tool = AiToolContext();

  late final AiToolExecutor _executor = AiToolExecutor.fromRef(_ref);

  /// 开始训练后解析失败时的提示
  static const workoutParseFailedMessage = '训练计划没解析出来，换个模板再试';

  late final AiChatSession _session = AiChatSession(
    ref: _ref,
    read: () => state,
    write: (next) => state = next,
    resetToolContext: _tool.reset,
    requestRound: _request,
  );

  AiChatNotifier(this._ref) : super(const AiChatState()) {
    _session.load();
  }

  /// 发送一条消息（[image] 不为空时走视觉消息，文本可留空）
  Future<void> send(String text, {File? image}) =>
      _session.send(text, image: image);

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() => _session.retryLast();

  /// 确认执行待确认的写操作
  Future<void> confirmTool() async {
    final preview = state.pendingTool;
    if (preview == null) return;
    state = state.copyWith(clearPendingTool: true, isStreaming: true);
    try {
      final result = await _executor.execute(preview.call);
      // 「开始训练」不落库：把槽位交给页面跳转，本轮到此为止
      // （训练页会盖在对话页上，模型再说话反而是干扰）
      if (preview.call.name == AiToolSpecs.startWorkout) {
        _handOffWorkoutStart(result);
        return;
      }
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

  /// 把 start_workout 的结果交给界面：只放状态，不请求模型
  void _handOffWorkoutStart(String result) {
    final intent = AiWorkoutIntent.parse(result);
    final failed = intent == null;
    state = state.copyWith(
      isStreaming: false,
      clearStreaming: true,
      clearError: !failed,
      error: failed ? workoutParseFailedMessage : null,
      pendingWorkoutStart: intent?.slots,
      pendingWorkoutTemplateName: intent?.templateName,
    );
  }

  /// 页面跳转完清空意图（否则从训练页返回会再跳一次）
  void consumeWorkoutStart() {
    state = state.copyWith(clearPendingWorkout: true);
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
  Future<void> saveApiKey(String key) => _session.saveApiKey(key);

  /// 清空聊天记录（同时丢弃工具上下文）
  Future<void> clearHistory() => _session.clearHistory();

  /// 错误展示后清空（页面消费）
  void consumeError() => _session.consumeError();
}

final aiChatProvider = StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
