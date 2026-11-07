import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:fittrack/core/services/cloud_voice_player.dart';
import 'package:fittrack/core/services/edge_tts_service.dart';
import 'package:fittrack/core/services/minimax_tts_service.dart';

/// 训练语音教练：TTS 播报 + 节拍器
class WorkoutCoach {
  static final WorkoutCoach _instance = WorkoutCoach._();
  factory WorkoutCoach() => _instance;
  WorkoutCoach._();

  /// 系统 TTS 引擎**懒创建**：单例在构造时就去建平台通道对象，
  /// 会让"只想用云端音色"的调用方（以及不经 Flutter binding 的单测）白白踩一次
  /// method channel。
  FlutterTts? _ttsInstance;
  FlutterTts get _tts => _ttsInstance ??= FlutterTts();

  Timer? _paceTimer;
  bool enabled = true;

  /// 是否已完成 TTS 引擎初始化（语言 / 音量 / 音色 / 语速）
  bool _inited = false;

  double _rate = 0.45;
  double _pitch = 1.0;
  String? _voiceName;

  /// 云端音色播放器；null = 未配置（走系统 TTS）
  CloudVoicePlayer? _cloud;

  /// 云端是否已启用（语音设置页据此显示"当前用云端"）
  bool get cloudEnabled => _cloud != null;

  /// 测试注入：系统播报实现（默认走 flutter_tts，测试里换成假的，别真调系统 TTS）
  @visibleForTesting
  Future<void> Function(String text)? systemSpeakOverride;

  /// 应用 **MiniMax（付费）** 音色配置。
  ///
  /// [apiKey] 为空 ⇒ 关闭云端，随后所有播报走系统 TTS。
  /// 这条路径必须永远可用：训练播报哑掉比音质差严重得多。
  void applyMinimaxConfig({
    String? apiKey,
    String? groupId,
    String? baseUrl,
    String? voiceId,
    double speed = 1.0,
    int pitch = 0,
    @visibleForTesting CloudVoicePlayer? player,
  }) {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) {
      disableCloud();
      return;
    }
    final id = (voiceId == null || voiceId.trim().isEmpty)
        ? 'female-shaonv'
        : voiceId.trim();
    final url = (baseUrl == null || baseUrl.trim().isEmpty)
        ? MinimaxTtsService.defaultBaseUrl
        : baseUrl.trim();
    _cloud = player ??
        CloudVoicePlayer(
          provider: 'minimax',
          voiceId: id,
          speed: speed,
          pitch: pitch,
          synthesize: (text) => MinimaxTtsService.synthesize(
            text: text,
            apiKey: key,
            groupId: groupId,
            voiceId: id,
            speed: speed,
            pitch: pitch,
            baseUrl: url,
          ),
        );
  }

  /// 懒初始化：首次播报前确保 TTS 语言等参数已设置（幂等，仅生效一次）
  ///
  /// 全项目原先没有任何地方调用 [init]，导致中文播报可能读错或无声，
  /// 因此改为在每次播报入口处按需触发。
  Future<void> _ensureInit() async {
    if (_inited) return;
    _inited = true; // 先置位，避免并发调用时重复初始化
    await init();
  }

  /// 初始化 TTS 引擎：中文语言 + 音量 + 语速/音色
  ///
  /// 模拟器或设备缺少 TTS 引擎时相关调用会抛异常，
  /// 此处逐个 try/catch 兜底，保证训练流程不因语音不可用而崩溃。
  Future<void> init() async {
    try {
      await _tts.setLanguage('zh-CN');
    } catch (_) {}
    try {
      await _tts.setVolume(1.0);
    } catch (_) {}
    await _applySettings();
  }

  /// 应用 **Edge TTS（免费）** 音色配置：不需要 Key，只要有 edgeVoiceId。
  ///
  /// [voiceId] 是 Edge 的 voice name（`zh-CN-XiaoxiaoNeural`）。
  void applyEdgeConfig({
    required String voiceId,
    double speed = 1.0,
    int pitch = 0,
    @visibleForTesting CloudVoicePlayer? player,
  }) {
    final id = voiceId.trim();
    if (id.isEmpty) {
      disableCloud();
      return;
    }
    _cloud = player ??
        CloudVoicePlayer(
          provider: 'edge',
          voiceId: id,
          speed: speed,
          pitch: pitch,
          synthesize: (text) => EdgeTtsService.synthesize(
            text: text,
            voiceId: id,
            speed: speed,
            pitch: pitch,
          ),
        );
  }

  /// 关闭云端/免费音色，回到系统 TTS
  void disableCloud() {
    _cloud?.stop();
    _cloud = null;
  }

  /// 预热倒计时常用短语（仅云端/Edge 音色，系统 TTS 无需）。
  ///
  /// 训练开始前先把「3 / 2 / 1 / 开始 / 休息 / 组 / 准备」合成缓存好，
  /// 倒计时 tick 到的时候瞬时播放、跟读秒同步，不因合成延迟而滞后/被掐断。
  ///
  /// 测试环境直接跳过：flutter_test 的 mock HttpClient 不支持 WebSocket，
  /// 真连网会冒出未捕获异常（预热只是生产环境的一次性优化，不是功能本身）。
  void prewarmCountdown() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') return;
    _cloud?.prewarm(const ['3', '2', '1', '开始', '休息', '组', '准备']);
  }

  /// 从外部设置语音参数（由调用方从 UserSettings 读取后传入）
  void applySettings({
    double rate = 0.45,
    double pitch = 1.0,
    String? voiceName,
  }) {
    _rate = rate;
    _pitch = pitch;
    _voiceName = voiceName;
    _applySettings();
  }

  Future<void> _applySettings() async {
    final voice = _voiceName;
    if (voice != null && voice.isNotEmpty) {
      try {
        await _tts.setVoice({'name': voice, 'locale': 'zh-CN'});
      } catch (_) {}
    }
    try {
      await _tts.setSpeechRate(_rate);
      await _tts.setPitch(_pitch);
    } catch (_) {}
  }

  /// 获取系统可用音色列表
  Future<List<Map<String, String>>> getVoices() async {
    try {
      final voices = await _tts.getVoices;
      return voices.where((v) {
        final locale = v['locale'];
        return locale is String && locale.startsWith('zh');
      }).map((v) {
        final name = v['name'];
        final locale = v['locale'];
        return {
          'name': name is String ? name : '',
          'locale': locale is String ? locale : '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    if (await _speakCloud(text)) return;
    await _systemSpeak(text);
  }

  /// 立即播报（先停止当前语音，避免队列堆积）
  Future<void> speakImmediate(String text) async {
    if (!enabled) return;
    if (_cloud != null) await _cloud!.stop();
    if (await _speakCloud(text)) return;
    await _systemSpeak(text, stopFirst: true);
  }

  /// 报数专用：**只走系统 TTS**，不走云端。
  ///
  /// 为什么：倒计时每秒一次，云端合成要 300~800ms 网络往返，还要先 stop 上一句，
  /// 结果"屏幕已经 42、耳朵听到 44"，而且数字经常被下一句截断。
  /// 系统 TTS 是本地合成（几十毫秒），才能跟屏幕对齐；句子仍用云端音色。
  Future<void> speakCount(String text) async {
    if (!enabled) return;
    if (_cloud != null) await _cloud!.stop();
    await _systemSpeak(text, stopFirst: true);
  }

  /// 尝试云端播报。成功返回 true；**任何异常都返回 false**（并 debugPrint），
  /// 由调用方回落系统 TTS —— 云端只负责更好听，绝不负责"能不能播"。
  Future<bool> _speakCloud(String text) async {
    final cloud = _cloud;
    if (cloud == null || text.trim().isEmpty) return false;
    try {
      await cloud.speak(text);
      return true;
    } catch (e) {
      debugPrint('云端音色失败，回落系统 TTS：$e');
      return false;
    }
  }

  Future<void> _systemSpeak(String text, {bool stopFirst = false}) async {
    final override = systemSpeakOverride;
    if (override != null) {
      await override(text);
      return;
    }
    await _ensureInit();
    try {
      if (stopFirst) await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  /// 停止当前播报并清空 TTS 队列
  Future<void> stop() async {
    await _cloud?.stop();
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void beep() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
    SystemSound.play(SystemSoundType.click);
  }

  void startPace(int intervalMs, VoidCallback onTick) {
    stopPace();
    _paceTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      beep();
      onTick();
    });
  }

  void stopPace() {
    _paceTimer?.cancel();
    _paceTimer = null;
  }

  Future<void> announceSetStart(String exerciseName, int setNumber) async {
    if (!enabled) return;
    await _ensureInit();
    await speak(exerciseName);
    await Future.delayed(const Duration(milliseconds: 800));
    await speak('开始');
    await Future.delayed(const Duration(milliseconds: 600));
    await speak('3');
    await Future.delayed(const Duration(milliseconds: 700));
    await speak('2');
    await Future.delayed(const Duration(milliseconds: 700));
    await speak('1');
    await Future.delayed(const Duration(milliseconds: 500));
    await speak('第${_numberToChinese(setNumber)}组');
  }

  Future<void> announceSetEnd(int setNumber) async {
    if (!enabled) return;
    await _ensureInit();
    await speak('第${_numberToChinese(setNumber)}组已结束');
  }

  Future<void> announceWorkoutDone() async {
    if (!enabled) return;
    await _ensureInit();
    await speak('训练完成，辛苦了');
  }

  Future<void> announceAbandon() async {
    if (!enabled) return;
    await _ensureInit();
    await speak('训练已取消');
  }

  String _numberToChinese(int n) {
    const map = {
      1: '一',
      2: '二',
      3: '三',
      4: '四',
      5: '五',
      6: '六',
      7: '七',
      8: '八',
      9: '九',
      10: '十',
      11: '十一',
      12: '十二',
      13: '十三',
      14: '十四',
      15: '十五',
      16: '十六',
      17: '十七',
      18: '十八',
      19: '十九',
      20: '二十',
    };
    return map[n] ?? '$n';
  }

  void dispose() {
    stopPace();
  }
}
