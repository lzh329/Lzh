import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/notifiers/workout_session_state.dart';

/// 播报模式：默认逐秒；用户选过的模式必须能跨会话记住
///
/// 用户实测：
/// 1) 默认要「逐秒播报」；
/// 2) 选了「末三秒播报」，退出再进模板又变回默认（缺少记录）。
void main() {
  test('默认模式是逐秒播报', () {
    expect(const WorkoutSessionState().countdownVoiceMode, 'every');
  });

  test('会话初始化：两种入口都从设置读模式', () {
    final src = File(
            'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
        .readAsStringSync();

    expect(src.contains('countdownVoiceMode: _defaultCountdownMode()'), isTrue);
    final occurrences =
        'countdownVoiceMode: _defaultCountdownMode()'.allMatches(src).length;
    expect(occurrences, 2, reason: '自由训练与计划训练两个入口都要带上');
  });

  test('设置已加载时也要把模式补进 state（旧代码在此直接 return）', () {
    final src = File(
            'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
        .readAsStringSync();

    final start = src.indexOf('void _loadTimerDefaults()');
    final end = src.indexOf('int _defaultTrainingSec()');
    expect(start, greaterThan(-1));
    final body = src.substring(start, end);

    expect(body.contains('final loaded = _ref.read(userSettingsProvider).valueOrNull;'),
        isTrue);
    expect(body.contains('state = state.copyWith('), isTrue,
        reason: '设置已加载是常见路径，必须在这里应用模式');
    expect(body.contains("loaded.countdownVoiceMode == 'last3'"), isTrue);
  });

  test('系统 TTS 的"播完"兜底存在（否则第一声就被掐断）', () {
    final coach =
        File('lib/core/services/workout_coach.dart').readAsStringSync();
    expect(coach.contains('text.runes.length * 170'), isTrue,
        reason: '部分机型忽略 awaitSpeakCompletion，需要按字数兜底等待');
  });
}
