import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 倒计时启动顺序：**先播完，再开始倒数**
///
/// 用户实测：动作名还没念完，倒计时已经走了 2~3 秒；休息报时同样。
/// 根因是"开口"和"启动计时"同时发生，且 speak() 在开口时就返回。
/// 这里用源码守卫锁住顺序（真实音频时序只能真机验）。
void main() {
  final notifier = File(
          'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
      .readAsStringSync();
  final coach =
      File('lib/core/services/workout_coach.dart').readAsStringSync();
  final player =
      File('lib/core/services/cloud_voice_player.dart').readAsStringSync();

  test('教练提供「播完才返回」的接口，云端与系统 TTS 都支持', () {
    expect(coach.contains('Future<void> speakAndWait('), isTrue);
    expect(player.contains('Future<void> speakAndWait('), isTrue);
    expect(coach.contains('awaitSpeakCompletion(true)'), isTrue,
        reason: '系统 TTS 默认开口即返回，必须临时切换成等播完');
  });

  test('训练：await 播报在前，_trainingCtrl.start 在后', () {
    final start = notifier.indexOf('Future<void> _startTrainingAsync()');
    final end = notifier.indexOf('void startTraining()');
    expect(start, greaterThan(-1));
    final body = notifier.substring(start, end);

    final speakIdx = body.indexOf('await _coach.speakAndWait');
    final ctrlIdx = body.indexOf('_trainingCtrl.start(');
    expect(speakIdx, greaterThan(-1), reason: '动作名必须用等待版播报');
    expect(ctrlIdx, greaterThan(speakIdx),
        reason: '必须先播完再启动倒计时（倒序就是老 bug）');
  });

  test('休息：await 播报在前，_restCtrl.start 在后', () {
    final start = notifier.indexOf('Future<void> _startRestAsync(');
    final end = notifier.indexOf('void stopRest()');
    expect(start, greaterThan(-1));
    final body = notifier.substring(start, end);

    final speakIdx = body.indexOf('await _coach.speakAndWait');
    final ctrlIdx = body.indexOf('_restCtrl.start(');
    expect(speakIdx, greaterThan(-1));
    expect(ctrlIdx, greaterThan(speakIdx),
        reason: '「休息 15 秒」没念完就倒数，是用户报的原问题');
  });

  test('播报期间被打断（暂停/跳过/切动作）不启动倒计时', () {
    final start = notifier.indexOf('Future<void> _startTrainingAsync()');
    final body = notifier.substring(start, notifier.indexOf('void startTraining()'));
    expect(body.contains('!state.isTraining'), isTrue);
    expect(body.contains('state.isTimerPaused'), isTrue);

    final restStart = notifier.indexOf('Future<void> _startRestAsync(');
    final restBody =
        notifier.substring(restStart, notifier.indexOf('void stopRest()'));
    expect(restBody.contains('!state.isResting'), isTrue);
    expect(restBody.contains('state.isRestPaused'), isTrue);
  });
}
