import 'dart:collection';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

/// 云端音色播放器：合成 → 缓存 → 播放 MP3 字节。
///
/// 两个关键设计：
/// 1. **内存 LRU 缓存（默认 64 条）**：训练播报是固定短语（"开始"/"3"/"2"/"第X组"），
///    不缓存的话一轮训练要打几十次合成接口 —— 又慢又花钱。key 里带 voiceId/speed/
///    pitch，换预设自然失效。
/// 2. **依赖可注入**：合成与播放都是函数类型的可选参数，测试里换成假的即可，
///    不需要真网络、不需要真的音频设备。
/// 3. **缓存 key 带 provider**：Edge 与 MiniMax 的同名预设是两段不同的音频。
class CloudVoicePlayer {
  /// 合成一句话 → MP3 字节（正式实现是 MiniMax，测试可换成假函数）
  final Future<Uint8List> Function(String text) _synthesize;

  /// 播放 MP3 字节（正式实现走 audioplayers，测试可计数/直接返回）
  final Future<void> Function(Uint8List bytes) _play;

  /// 停止播放
  final Future<void> Function() _stop;

  /// 播放并**等到播完**（用于"先报动作名，再开始倒计时"）
  final Future<void> Function(Uint8List bytes) _playAndWait;

  final int capacity;

  /// key → 音频字节（LinkedHashMap 天然保序，用来做 LRU）
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();

  /// 缓存键的一部分：同一个文本在不同音色/语速下是**不同**的音频
  final String _cachePrefix;

  CloudVoicePlayer({
    required Future<Uint8List> Function(String text) synthesize,
    /// 供应商（`edge` / `minimax`）：**必须进缓存 key** ——
    /// 否则同一个 voiceId 名（或同名预设）在两套音色间会串音
    required String provider,
    required String voiceId,
    double speed = 1.0,
    int pitch = 0,
    this.capacity = 64,
    Future<void> Function(Uint8List bytes)? play,
    Future<void> Function(Uint8List bytes)? playAndWait,
    Future<void> Function()? stop,
  })  : _synthesize = synthesize,
        _cachePrefix = '$provider|$voiceId|${speed.toStringAsFixed(2)}|$pitch|',
        _play = play ?? _playWithAudioplayers,
        _playAndWait = playAndWait ?? _playAndWaitWithAudioplayers,
        _stop = stop ?? _stopWithAudioplayers;

  /// 缓存命中数（测试用：证明第二次没打接口）
  int get cachedCount => _cache.length;

  /// 这段文本是否已经合成过 —— 倒计时报数用它决定"用云端还是就地系统 TTS"
  bool hasCached(String text) => _cache.containsKey('$_cachePrefix$text');

  /// 合成并播放。失败**向上抛**，由 [WorkoutCoach] 决定是否回落系统 TTS。
  Future<void> speak(String text) async {
    await _play(await _bytesFor(text));
  }

  /// 播完才返回：播报期间不要开始倒计时（否则名字没念完，秒数已经在走）
  Future<void> speakAndWait(String text) async {
    await _playAndWait(await _bytesFor(text));
  }

  Future<Uint8List> _bytesFor(String text) async {
    final key = '$_cachePrefix$text';
    final hit = _cache[key];
    if (hit != null) {
      // 命中即刷新到队尾（LRU）
      _cache.remove(key);
      _cache[key] = hit;
      return hit;
    }
    final bytes = await _synthesize(text);
    _put(key, bytes);
    return bytes;
  }

  /// 预热：把常用短语先合成并缓存（**不播放**）。
  ///
  /// 倒计时是固定短语（"3"/"2"/"1"/"开始"…），如果等 tick 到了才现合成，
  /// 云端 TTS 的合成延迟会让数字滞后、被下一秒打断（读不全、不同步）。
  /// 训练开始前预热一轮，倒计时时命中缓存、瞬时播放，跟读秒同步。
  Future<void> prewarm(List<String> texts) async {
    for (final text in texts) {
      final key = '$_cachePrefix$text';
      if (_cache.containsKey(key)) continue;
      try {
        _put(key, await _synthesize(text));
      } catch (e) {
        // 预热失败静默忽略：真正播报时会重试 + 由 WorkoutCoach 回落系统 TTS
        debugPrint('预热短语失败（忽略）：$e');
      }
    }
  }

  /// 直接播一段字节（试听用：不缓存、不回落、不参与 LRU）
  static Future<void> playOnce(Uint8List bytes) => _playWithAudioplayers(bytes);

  Future<void> stop() async {
    try {
      await _stop();
    } catch (e) {
      debugPrint('云语音停止失败（忽略）：$e');
    }
  }

  void _put(String key, Uint8List bytes) {
    // 空字节不缓存：缓存了也播不出声，下次还该重试
    if (bytes.isEmpty) return;
    if (_cache.length >= capacity) {
      _cache.remove(_cache.keys.first); // 淘汰最久未用
    }
    _cache[key] = bytes;
  }

  /// 测试/调试：清空缓存
  @visibleForTesting
  void clearCache() => _cache.clear();

  // ── 默认实现（真实播放） ──

  static final AudioPlayer _player = AudioPlayer();

  /// 播放并等待自然结束（超时兜底：被 stop 打断时不会一直挂着）
  static Future<void> _playAndWaitWithAudioplayers(Uint8List bytes) async {
    await _player.stop();
    final done = _player.onPlayerComplete.first;
    await _player.play(BytesSource(bytes));
    try {
      await done.timeout(const Duration(seconds: 12));
    } catch (_) {}
  }

  static Future<void> _playWithAudioplayers(Uint8List bytes) async {
    await _player.stop();
    await _player.play(BytesSource(bytes));
  }

  static Future<void> _stopWithAudioplayers() => _player.stop();
}
