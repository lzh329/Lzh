import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 训练语音教练：TTS 播报 + 节拍器
class WorkoutCoach {
  static final WorkoutCoach _instance = WorkoutCoach._();
  factory WorkoutCoach() => _instance;
  WorkoutCoach._();

  final FlutterTts _tts = FlutterTts();

  Timer? _paceTimer;
  bool enabled = true;

  /// 是否已完成 TTS 引擎初始化（语言 / 音量 / 音色 / 语速）
  bool _inited = false;

  double _rate = 0.45;
  double _pitch = 1.0;
  String? _voiceName;

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
      return voices
        .where((v) {
          final locale = v['locale'];
          return locale is String && locale.startsWith('zh');
        })
        .map((v) {
          final name = v['name'];
          final locale = v['locale'];
          return {
            'name': name is String ? name : '',
            'locale': locale is String ? locale : '',
          };
        })
        .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> speak(String text) async {
    if (!enabled) return;
    await _ensureInit();
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  /// 立即播报（先停止当前语音，避免队列堆积）
  Future<void> speakImmediate(String text) async {
    if (!enabled) return;
    await _ensureInit();
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  /// 停止当前播报并清空 TTS 队列
  Future<void> stop() async {
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
      1: '一', 2: '二', 3: '三', 4: '四', 5: '五',
      6: '六', 7: '七', 8: '八', 9: '九', 10: '十',
      11: '十一', 12: '十二', 13: '十三', 14: '十四', 15: '十五',
      16: '十六', 17: '十七', 18: '十八', 19: '十九', 20: '二十',
    };
    return map[n] ?? '$n';
  }

  void dispose() {
    stopPace();
  }
}
