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

/// 跑一轮模型请求的入口（生产走 [AiChatRoundResult.run]，测试注入假实现）
typedef AiChatRoundRunner = Future<AiChatRoundResult> Function({
  required String apiKey,
  required List<AiMessage> messages,
  required void Function(String delta) onDelta,
  double temperature,
  bool webEnabled,
});

/// 嘎教练对话状态机：流式回复 + 工具回合（写操作必须由用户点头）
///
/// 会话事务（发送 / 重试 / 历史 / Key）在 [AiChatSession]。
class AiChatNotifier extends StateNotifier<AiChatState> {
  final Ref _ref;

  /// 当前轮的工具上下文（assistant tool_calls + tool 结果）
  final AiToolContext _tool = AiToolContext();

  /// 测试注入点；null = 生产路径
  final AiChatRoundRunner? _roundRunnerOverride;

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

  AiChatNotifier(this._ref, {AiChatRoundRunner? roundRunner})
      : _roundRunnerOverride = roundRunner,
        super(const AiChatState()) {
    _session.load();
  }

  /// 发送一条消息（[image] 不为空时走视觉消息，文本可留空）
  Future<void> send(String text, {File? image}) =>
      _session.send(text, image: image);

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() => _session.retryLast();

  /// 追加一条**可见的操作留痕**（assistant 消息 + 落库）
  ///
  /// 背景（需求 #2「操作确认留痕」）：此前工具执行成功后，结果只进工具上下文
  /// `_tool`，要等下一轮模型说话才可能被提及 —— 对话流里看不到任何痕迹，
  /// 用户只能靠猜。「实际执行状态」与「对话展示状态」必须一致，所以每一步
  /// 都在这里留一条肉眼可见的记录。
  ///
  /// 落库失败不阻断流程：留痕是锦上添花，真正的事实记录在工具上下文里。
  Future<void> _appendActionTrace(String text) async {
    state = state.copyWith(
      messages: [
        ...state.messages,
        AiMessage(role: 'assistant', content: text),
      ],
    );
    try {
      await _ref.read(aiChatRepoProvider).add('assistant', text);
    } catch (e) {
      debugPrint('操作留痕落库失败: $e');
    }
  }

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
      // 成功留痕：用 preview 的现成文案，不为每个工具重写
      await _appendActionTrace('✅ 已执行：${preview.label}：${preview.detail}');
      await _request();
    } on AiToolException catch (e) {
      // 失败也要回执进上下文并继续一轮：模型知道"没做成、为什么"才会向用户
      // 解释或换方式重试。只弹 toast 的话模型不知情，下一轮会幻觉"已建好"。
      _tool.append(preview.call, AiToolContext.failureReceipt(e.message));
      await _appendActionTrace('❌ ${preview.label}失败：${e.message}');
      await _request();
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
    await _appendActionTrace('🚫 已取消：${preview.label}：${preview.detail}');
    await _request();
  }

  /// 把 start_workout 的结果交给界面：只放状态，不请求模型
  void _handOffWorkoutStart(String result) {
    final intent = AiWorkoutIntent.parse(result);
    final failed = intent == null;
    // start_workout 不走 _request()（跳训练页，模型再说话是干扰），
    // 所以它的留痕要在这里单独补上，否则跳页后对话里没有任何记录。
    if (!failed) {
      _appendActionTrace('✅ 已执行：开始训练：${intent.templateName}');
    }
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

      final round = await (_roundRunnerOverride ?? AiChatRoundResult.run)(
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
      // 模型随工具调用说出口的正文也要落进历史：否则对话里只剩一条孤零零的
      // 用户消息，工具一旦失败，用户面对的就是"发出去没回音"
      if (round.toolCalls.isNotEmpty) {
        if (round.content.trim().isNotEmpty) {
          await _ref.read(aiChatRepoProvider).add('assistant', round.content);
          state = state.copyWith(
            messages: [
              ...state.messages,
              AiMessage(role: 'assistant', content: round.content),
            ],
          );
        }
        await _handleToolCalls(round.toolCalls);
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
  ///
  /// 一轮可能带多个调用：只读的依次执行；遇到需要确认的写操作就停下等用户
  /// 点头，剩下的等下一轮。**失败的调用同样回执（ok:false + 原因）**——这是
  /// 2026-10-28「AI 说建好了模板但模板页没有」事故的根修：失败如果只变成
  /// 一个 toast，模型不知情，下一轮就会幻觉成功。
  Future<void> _handleToolCalls(List<AiToolCall> calls) async {
    for (final call in calls) {
      if (_tool.round >= AiToolLimits.maxCallsPerRound) {
        // 超限：把回执留给模型（下次用户发消息时它知道为什么中断），本轮终止
        _tool.append(
            call, AiToolContext.failureReceipt(AiToolLimits.overLimitMessage));
        state = state.copyWith(isStreaming: false, clearStreaming: true);
        return;
      }
      _tool.round++;
      try {
        final preview = await _executor.preview(call);
        if (preview.needsConfirm) {
          state = state.copyWith(
              isStreaming: false, clearStreaming: true, pendingTool: preview);
          return;
        }
        final result = await _executor.execute(call);
        _tool.append(call, result);
      } on AiToolException catch (e) {
        _tool.append(call, AiToolContext.failureReceipt(e.message));
      }
    }
    await _request();
  }

  /// 保存用户填写的 API Key
  Future<void> saveApiKey(String key) => _session.saveApiKey(key);

  /// 清空聊天记录（同时丢弃工具上下文）
  Future<void> clearHistory() => _session.clearHistory();

  /// 错误展示后清空（页面消费）
  void consumeError() => _session.consumeError();
}

final aiChatProvider =
    StateNotifierProvider<AiChatNotifier, AiChatState>((ref) {
  return AiChatNotifier(ref);
});
