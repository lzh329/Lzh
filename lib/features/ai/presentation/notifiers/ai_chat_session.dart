import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';

/// 聊天会话的后台事务：初始化、发送、重试、清空历史、保存 Key
///
/// 从 [AiChatNotifier] 抽出来，是为了让状态机只留「流式回复 + 工具确认闸门」
/// 这两件真正需要仔细审的事。这里的方法都要读写 ref 与历史表，
/// 状态由外部通过 [read] / [write] 注入，因此本类自己不持有 state。
class AiChatSession {
  final Ref _ref;

  /// 读取当前状态（由 notifier 提供）
  final AiChatState Function() _read;

  /// 写回状态（由 notifier 提供）
  final void Function(AiChatState) _write;

  /// 丢掉本轮工具上下文（新一轮对话 / 重试 / 清空历史时调用）
  final void Function() _resetToolContext;

  /// 发起一轮模型请求（由 notifier 提供）
  final Future<void> Function() _requestRound;

  /// 最近一次用户消息内容（失败后供「重试」复用，不重复入库；图片消息也能重试）
  Object? _lastUserContent;

  AiChatSession({
    required Ref ref,
    required AiChatState Function() read,
    required void Function(AiChatState) write,
    required void Function() resetToolContext,
    required Future<void> Function() requestRound,
  })  : _ref = ref,
        _read = read,
        _write = write,
        _resetToolContext = resetToolContext,
        _requestRound = requestRound;

  /// 载入设置里的 Key 状态与历史消息
  Future<void> load() async {
    final settings = await _ref.read(userSettingsProvider.future);
    final key = AiService.resolveKey(settings?.aiApiKey);
    final history = await _ref.read(aiChatRepoProvider).getHistory();
    _write(_read().copyWith(messages: history, hasKey: key != null));
  }

  /// 发送一条消息（[image] 不为空时走视觉消息，文本可留空）
  Future<void> send(String text, {File? image}) async {
    final trimmed = text.trim();
    final state = _read();
    if ((trimmed.isEmpty && image == null) || state.isBusy) return;
    if (!state.hasKey) {
      _write(state.copyWith(
          error: '请先点右上角钥匙图标，配置 DeepSeek API Key'));
      return;
    }
    final prepared = await AiUserPayloadResult.load(text: trimmed, image: image);
    final payload = prepared.payload;
    if (payload == null) {
      _write(_read().copyWith(error: prepared.error));
      return;
    }
    _lastUserContent = payload.content;
    _resetToolContext();
    _write(_read().copyWith(
      messages: [
        ..._read().messages,
        AiMessage(role: 'user', content: payload.content),
      ],
      clearError: true,
      // 用户用打字代替了点确认/取消 → 旧确认卡就地作废。
      // 不清的话它永远挂在输入框上方（2026-10-28 真实事故），而且工具上下文
      // 已被 reset，这张卡就算被点确认也接不上原来的轮次。
      clearPendingTool: true,
    ));
    // 数据库只存文本，图片用「[图片]」占位
    await _ref.read(aiChatRepoProvider).add('user', payload.historyText);
    await _requestRound();
  }

  /// 失败后重试上一条（用户消息已在历史里，不重复写入）
  Future<void> retryLast() async {
    if (_lastUserContent == null || _read().isBusy) return;
    _resetToolContext();
    await _requestRound();
  }

  /// 保存用户填写的 API Key
  Future<void> saveApiKey(String key) async {
    final trimmed = key.trim();
    await _ref.read(userSettingsRepoProvider).save(aiApiKey: trimmed);
    _ref.invalidate(userSettingsProvider);
    _write(_read().copyWith(hasKey: AiService.resolveKey(trimmed) != null));
  }

  /// 清空聊天记录（同时丢弃工具上下文与未执行的「开始训练」）
  Future<void> clearHistory() async {
    await _ref.read(aiChatRepoProvider).clear();
    _resetToolContext();
    _write(_read().copyWith(
      messages: const [],
      clearStreaming: true,
      clearPendingTool: true,
      clearPendingWorkout: true,
    ));
  }

  /// 错误展示后清空
  void consumeError() => _write(_read().copyWith(clearError: true));
}
