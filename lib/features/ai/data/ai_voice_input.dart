import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 把「已有文字」和「本次识别文字」拼成一段，重复内容不重复追加
///
/// 语音输入是流式的：同一个片段会以中间结果反复回来（"今天" → "今天练了"），
/// 所以合并规则必须是幂等的，否则输入框会被越拼越乱：
/// - `recognized` 为空 → 原样返回 `existing`（中间结果抖动时不清空用户输入）
/// - 已有文字为空 → 直接用 `recognized`
/// - `recognized` 已经包含已有文字（累积型中间结果）→ 用 `recognized`（不重复）
/// - 已有文字已包含这段识别结果（重复同一句）→ 保持 `existing` 不变
/// - 其余情况 → 追加，中文/标点/空格处不额外插空格，英文单词之间补一个空格
String mergeVoiceText(String existing, String recognized) {
  final recognizedText = recognized.trim();
  if (recognizedText.isEmpty) return existing;
  final trimmedExisting = existing.trim();
  if (trimmedExisting.isEmpty) return recognizedText;
  // 识别结果是累积型的（把已有文字又念了一遍 / 是它的延长版）：直接用新的
  if (recognizedText == trimmedExisting ||
      recognizedText.startsWith(trimmedExisting)) {
    return recognizedText;
  }
  // 已有文字里已经有这段（同一句重复出现）：不追加
  if (trimmedExisting.contains(recognizedText)) return existing;
  final separator = _needSpaceAfter(existing) ? ' ' : '';
  return '$existing$separator$recognizedText';
}

/// 追加前是否要补一个空格：只在英文 / 数字结尾时补（中文直接接上更自然）
bool _needSpaceAfter(String text) {
  if (text.isEmpty) return false;
  final last = text.substring(text.length - 1);
  if (last.trim().isEmpty) return false; // 尾部已有空白
  return RegExp(r'[A-Za-z0-9]').hasMatch(last);
}

/// 应用内语音输入（封装 speech_to_text）
///
/// 设计约定：**任何平台异常都收敛成可读中文提示**，绝不向 UI 抛异常 ——
/// 桌面 / 无识别服务的设备上点麦克风只会弹一句提示，不会崩。
/// 页面进入时不预初始化，第一次点麦克风才 [init]（省一次权限弹窗）。
class AiVoiceInput {
  AiVoiceInput();

  static const localeId = 'zh_CN';
  static const listenFor = Duration(seconds: 30);
  static const pauseFor = Duration(seconds: 3);

  /// 缺识别服务 / 跳转系统设置之类的通用错误文案
  static const unavailableMessage = '没有可用的语音识别服务';
  static const permissionMessage = '麦克风权限被拒绝，请到系统设置里允许';
  static const genericErrorMessage = '语音识别出错了，再说一次试试';

  final SpeechToText _engine = SpeechToText();

  bool _initialized = false;
  String? _lastError;

  /// 是否正在听（平台状态为准，超时 / 出错也会变 false）
  bool get isListening => _engine.isListening;

  /// 最近一次错误的可读中文文案（null = 没有错误）
  String? get lastError => _lastError;

  /// 监听状态变化（按钮样式 / hint 用）：true = 开始听，false = 已结束
  void Function(bool listening)? onListeningChanged;

  /// 识别过程中的错误（已转中文），用于 SnackBar 提示
  void Function(String message)? onError;

  /// 检查可用性并请求麦克风权限；false = 这台设备用不了语音输入
  Future<bool> init() async {
    if (_initialized) return true;
    _lastError = null;
    try {
      final ok = await _engine.initialize(
        onError: _handlePlatformError,
        onStatus: (status) => onListeningChanged?.call(_engine.isListening),
        finalTimeout: const Duration(seconds: 2),
      );
      if (!ok) {
        _lastError = unavailableMessage;
        return false;
      }
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('语音初始化失败: $e');
      _lastError = _describe(e);
      return false;
    }
  }

  /// 开始识别；[onResult] 会在中间结果（isFinal=false）与最终结果时被调用
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    final ready = await init();
    if (!ready) {
      onError?.call(_lastError ?? unavailableMessage);
      return;
    }
    _lastError = null;
    try {
      await _engine.listen(
        onResult: (result) => onResult(result.recognizedWords, result.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          // 出错就自动收尾，避免按钮一直停在"录音中"
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      onListeningChanged?.call(_engine.isListening);
    } catch (e) {
      debugPrint('语音识别启动失败: $e');
      _lastError = _describe(e);
      onListeningChanged?.call(false);
      onError?.call(_lastError!);
    }
  }

  /// 结束识别：平台会补发一次最终结果（已识别的话先写进输入框再收尾）
  Future<void> stop() async {
    try {
      if (_initialized) await _engine.stop();
    } catch (e) {
      debugPrint('语音识别停止失败: $e');
    }
    onListeningChanged?.call(false);
  }

  /// 丢弃本次识别（页面 dispose / 发送消息时用，不要最终结果）
  Future<void> cancel() async {
    try {
      if (_initialized) await _engine.cancel();
    } catch (e) {
      debugPrint('语音识别取消失败: $e');
    }
    onListeningChanged?.call(false);
  }

  /// 平台错误 → 中文提示（错误码不直接给用户看）
  void _handlePlatformError(SpeechRecognitionError error) {
    _lastError = switch (error.errorMsg) {
      'error_no_match' => '没听清，再说一次试试',
      'error_permission' || 'error_audio_error' => permissionMessage,
      'error_network' || 'error_network_timeout' => '语音识别需要联网，检查一下网络',
      'error_busy' => '麦克风被别的应用占用了，稍后再试',
      'error_speech_timeout' => '没听到声音，再点一下麦克风试试',
      _ => genericErrorMessage,
    };
    onListeningChanged?.call(_engine.isListening);
    onError?.call(_lastError!);
  }

  /// 异常 → 中文提示（桌面 / 无插件实现会走到这里）
  static String _describe(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('missingplugin') || text.contains('unimplemented')) {
      return unavailableMessage;
    }
    if (text.contains('permission')) return permissionMessage;
    if (text.contains('notinitialized')) return unavailableMessage;
    return genericErrorMessage;
  }
}
