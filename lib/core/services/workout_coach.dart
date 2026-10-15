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

  double _rate = 0.45;
  double _pitch = 1.0;
  String? _voiceName;

  Future<void> init() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setVolume(1.0);
    _applySettings();
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
    await _tts.setSpeechRate(_rate);
    await _tts.setPitch(_pitch);
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
    await _tts.speak(text);
  }

  /// 立即播报（先停止当前语音，避免队列堆积）
  Future<void> speakImmediate(String text) async {
    if (!enabled) return;
    await _tts.stop();
    await _tts.speak(text);
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
    await speak('第${_numberToChinese(setNumber)}组已结束');
  }

  Future<void> announceWorkoutDone() async {
    if (!enabled) return;
    await speak('训练完成，辛苦了');
  }

  Future<void> announceAbandon() async {
    if (!enabled) return;
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
