import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:edge_tts/edge_tts.dart';

/// Edge TTS 合成失败。`message` 面向用户，可直接显示。
class EdgeTtsException implements Exception {
  final String message;

  const EdgeTtsException(this.message);

  @override
  String toString() => 'EdgeTtsException: $message';
}

/// 真正干活的合成函数（可注入：测试里换成假实现，绝不真连 WebSocket）
typedef EdgeSynthesize = Future<Uint8List> Function({
  required String text,
  required String voiceId,
  required String rate,
  required String pitch,
});

/// Edge TTS（微软 Edge 的朗读接口）—— **免费、无需 Key** 的音色通道。
///
/// 为什么加它：系统 TTS 的音质完全看手机（低端机上像机器人），而 MiniMax 要先
/// 申请 Key、按量付费。Edge 的神经网络音色质量接近商用、且不需要配置 ——
/// 让"什么 Key 都没有"的用户也能听个像样的人声。
///
/// 代价（必须如实告知用户）：这是**非官方接口**，走 `speech.platform.bing.com`，
/// 可能随时失效；所以它只负责"更好听"，一旦失败一律回落系统 TTS。
class EdgeTtsService {
  EdgeTtsService._();

  /// 兜底音色（晓晓）：中文最稳、断句自然
  static const defaultVoiceId = 'zh-CN-XiaoxiaoNeural';

  static const requestTimeout = Duration(seconds: 20);

  /// 倍速 → Edge 的 `rate`（`+5%` / `-5%`，四舍五入到整数百分比）
  ///
  /// Edge 只认 `^[+-]\d+%$`，所以必须带符号、且必须是整数。
  static String rateOf(double speed) {
    final pct = ((speed - 1.0) * 100).round();
    return '${pct >= 0 ? '+' : ''}$pct%';
  }

  /// 音调（-12~12）→ Edge 的 `pitch`（每档 10Hz：-3 → `-30Hz`）
  static String pitchOf(int pitch) {
    final hz = pitch * 10;
    return '${hz >= 0 ? '+' : ''}${hz}Hz';
  }

  /// 合成为 MP3 字节。失败抛 [EdgeTtsException]（文案给用户看）
  ///
  /// [synth] 只给单测注入用；正式运行传 null，走 [Communicate]。
  static Future<Uint8List> synthesize({
    required String text,
    required String voiceId,
    double speed = 1.0,
    int pitch = 0,
    EdgeSynthesize? synth,
  }) async {
    final trimmed = text.trim();
    // 空文本不发请求：既省一次网络往返，也避免拿到 0 字节被当成"成功"
    if (trimmed.isEmpty) {
      throw const EdgeTtsException('要播报的文字是空的');
    }
    if (voiceId.trim().isEmpty) {
      throw const EdgeTtsException('还没选音色');
    }

    final run = synth ?? _defaultSynthesize;
    try {
      final bytes = await run(
        text: trimmed,
        voiceId: voiceId.trim(),
        rate: rateOf(speed),
        pitch: pitchOf(pitch),
      );
      if (bytes.isEmpty) {
        throw const EdgeTtsException('免费音色这次没返回音频，稍后再试');
      }
      return bytes;
    } on EdgeTtsException {
      rethrow;
    } catch (e) {
      // 网络 / DNS / WebSocket 断开 / 接口改版：细节只进日志，
      // 给用户的是一句干净的提示（绝不把原始异常 + token 甩到界面上）
      debugPrint('Edge TTS 合成失败：$e');
      throw const EdgeTtsException('免费音色暂时用不了，已改用系统音色');
    }
  }

  /// 真实实现：Edge 的流式合成，收集全部 MP3 分片
  static Future<Uint8List> _defaultSynthesize({
    required String text,
    required String voiceId,
    required String rate,
    required String pitch,
  }) async {
    final communicate = Communicate(
      text: text,
      voice: voiceId,
      rate: rate,
      pitch: pitch,
    );
    return communicate.toBytes().timeout(requestTimeout);
  }
}
