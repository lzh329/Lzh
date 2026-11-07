import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「停止计时 = 冻结、可继续」的回归守卫。
///
/// 背景（用户实测）：原来点「停止计时」会 cancel + 清零，界面回落到动作目标
/// 时长，看起来像"从头开始"，且无法接着倒数 → 只能直接点完成。
///
/// 这里用源码守卫锁住三处必须同时成立的实现（成本低、直击回归点）；
/// 真实交互由真机验证，避免为了测 Timer 引入脆弱的时间依赖。
void main() {
  test('暂停不清零：pauseTraining 保留 trainingSeconds 并置 isTimerPaused', () {
    final src = File(
            'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
        .readAsStringSync();

    expect(src.contains('void pauseTraining()'), isTrue,
        reason: '必须有独立的暂停入口');
    expect(src.contains('void resumeTraining()'), isTrue,
        reason: '必须有继续入口');

    // pauseTraining 的方法体里不许出现 trainingSeconds: 0（清零就是老 bug）
    final pauseBody = _methodBody(src, 'void pauseTraining()');
    expect(pauseBody.contains('trainingSeconds: 0'), isFalse,
        reason: '暂停不能把秒数清零');
    expect(pauseBody.contains('isTimerPaused: true'), isTrue,
        reason: '暂停必须置暂停标记');

    // resume 必须从冻结值启动倒计时，而不是从 _startTraining() 全套重来
    final resumeBody = _methodBody(src, 'void resumeTraining()');
    expect(resumeBody.contains('state.trainingSeconds'), isTrue,
        reason: '继续必须用冻结的剩余秒数');
    expect(resumeBody.contains('_trainingCtrl.start('), isTrue);
  });

  test('展示层：暂停时显示冻结秒数，并给出明确状态文案', () {
    final src =
        File('lib/features/workout/presentation/pages/workout_active_page.dart')
            .readAsStringSync();
    expect(
        src.contains(
            'if (state.isTraining || state.isTimerPaused) return state.trainingSeconds;'),
        isTrue,
        reason: '暂停时必须继续显示 trainingSeconds，否则会回落到目标时长（看起来从头开始）');
    expect(src.contains('已暂停'), isTrue, reason: '状态行要告诉用户当前是暂停');
  });

  test('工具行：自动模式显示「停止计时」，暂停后变「继续计时」', () {
    final src = File(
            'lib/features/workout/presentation/widgets/active_workout_tool_row.dart')
        .readAsStringSync();
    expect(src.contains("'暂停计时'"), isTrue);
    expect(src.contains("'继续计时'"), isTrue);
    expect(src.contains('isTimerPaused'), isTrue);
  });

  test('休息倒计时同样可暂停/继续，且「跳过」是独立动作', () {
    final notifier = File(
            'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
        .readAsStringSync();
    expect(notifier.contains('void pauseRest()'), isTrue);
    expect(notifier.contains('void resumeRest()'), isTrue);

    final pauseBody = _methodBody(notifier, 'void pauseRest()');
    expect(pauseBody.contains('_autoStartTimedIfNeeded'), isFalse,
        reason: '暂停休息绝不能顺手开始下一段倒计时（那正是"从头开始"的来源）');

    final row = File(
            'lib/features/workout/presentation/widgets/active_workout_tool_row.dart')
        .readAsStringSync();
    expect(row.contains("'暂停休息'"), isTrue);
    expect(row.contains("'继续休息'"), isTrue);
    expect(row.contains("'跳过休息'"), isTrue);
  });

  test('底部主按钮同样走暂停/继续，不是 stopAutoMode（清零退出）', () {
    final src =
        File('lib/features/workout/presentation/pages/workout_active_page.dart')
            .readAsStringSync();

    expect(src.contains("'暂停计时'"), isTrue, reason: '按钮文案要与行为一致');
    expect(src.contains("'继续计时'"), isTrue);

    final body = _methodBody(src, 'void _onPrimaryTap(');
    expect(body.contains('notifier.pauseTraining()'), isTrue,
        reason: '自动模式下的主按钮必须是暂停');
    expect(body.contains('notifier.resumeTraining()'), isTrue,
        reason: '暂停后主按钮必须是继续');
    expect(body.contains('notifier.stopAutoMode()'), isFalse,
        reason: '主按钮调 stopAutoMode 会把秒数清零 → 界面回落目标时长（老 bug）');
  });

  test('暂停时「下一个动作」仍可点（仅倒计时进行中禁用）', () {
    final src =
        File('lib/features/workout/presentation/pages/workout_active_page.dart')
            .readAsStringSync();
    expect(src.contains('canSkipExercise: !sessionState.isAutoMode,'), isTrue,
        reason: '不能再用 isTimerPaused 把暂停态的跳过动作一起禁掉');
  });

  test('倒计时朗读支持两种模式：全亮 / 321', () {
    final notifier = File(
            'lib/features/workout/presentation/notifiers/workout_session_notifier.dart')
        .readAsStringSync();
    expect(notifier.contains("countdownVoiceMode == 'every'"), isTrue,
        reason: '每 tick 都要按模式决定是否朗读');
    expect(notifier.contains('void setCountdownVoiceMode('), isTrue);

    final page = File(
            'lib/features/workout/presentation/pages/workout_active_page.dart')
        .readAsStringSync();
    final coach = File('lib/core/services/workout_coach.dart').readAsStringSync();
    expect(coach.contains('Future<void> speakCount('), isTrue,
        reason: '报数需要低延迟通道');
    expect(notifier.contains('_coach.speakCount('), isTrue,
        reason: '倒计时 tick 必须用系统 TTS 报数，云端合成会慢半拍');
    expect(page.contains("'逐秒播报'"), isTrue);
    expect(page.contains("'末三秒播报'"), isTrue);
  });
}

/// 取一个方法的方法体（从签名后第一个 `{` 到配平的 `}`）
String _methodBody(String src, String signature) {
  final start = src.indexOf(signature);
  if (start < 0) return '';
  final open = src.indexOf('{', start);
  if (open < 0) return '';
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return '';
}
