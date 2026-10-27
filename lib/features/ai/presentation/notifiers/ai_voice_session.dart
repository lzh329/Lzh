import 'package:flutter/widgets.dart';

import 'package:fittrack/features/ai/data/ai_voice_input.dart';

/// 输入栏的语音听写会话（状态机，与 UI 解耦便于单测）
///
/// 负责三件事：开始 / 结束听写、把识别结果合并进输入框（[mergeVoiceText]）、
/// 把 [AiVoiceInput] 的异常收敛成一句中文提示回调。UI 只管按钮样式和提示。
class AiVoiceSession extends ChangeNotifier {
  AiVoiceSession({required this.voice, required this.controller}) {
    voice.onListeningChanged = _setListening;
    voice.onError = _reportError;
  }

  final AiVoiceInput voice;
  final TextEditingController controller;

  /// 出错时的提示出口（UI 弹 SnackBar）
  void Function(String message)? onMessage;

  bool _listening = false;

  /// 开始听之前输入框里的内容：中间结果要在它基础上合并，不能越拼越长
  String _baseText = '';

  /// 发送消息后为 true：丢弃「停止」才补发的最终结果，避免把已发出的字填回来
  bool _discardResults = false;

  bool get listening => _listening;

  /// 点麦克风：正在听就停，否则先初始化再开始听
  Future<void> toggle() async {
    if (_listening) {
      await voice.stop();
      return;
    }
    final ready = await voice.init();
    if (!ready) {
      _reportError(voice.lastError ?? AiVoiceInput.unavailableMessage);
      return;
    }
    _discardResults = false;
    _baseText = controller.text;
    _setListening(true);
    await voice.start(onResult: _onResult);
  }

  /// 发送前的收尾：正在听就先停（随后补发的最终结果直接丢弃）
  Future<void> stopForSend() async {
    if (!_listening) return;
    _discardResults = true;
    await voice.stop();
  }

  /// 页面销毁：解绑回调并丢弃本次识别，别让识别服务一直占着麦克风
  Future<void> cancel() async {
    voice.onListeningChanged = null;
    voice.onError = null;
    await voice.cancel();
  }

  /// 识别结果写进输入框：保留用户已有文字，中间结果覆盖式更新（不累加）
  void _onResult(String text, bool isFinal) {
    if (_discardResults) return;
    final merged = mergeVoiceText(_baseText, text);
    if (merged == controller.text) return;
    controller.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(offset: merged.length),
    );
  }

  void _reportError(String message) => onMessage?.call(message);

  void _setListening(bool value) {
    if (_listening == value) return;
    _listening = value;
    notifyListeners();
  }
}
