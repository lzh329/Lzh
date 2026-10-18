import 'package:flutter/material.dart';

import 'active_workout_style.dart';

/// 训练执行页工具行（横向滚动的紧凑胶囊按钮）。
///
/// 承载原页面里的次级控制：上一组 / 计时训练 / 休息开关 / 训练与休息时长
/// 设置 / 节拍间隔 / 语音播报。纯展示 + 回调，具体逻辑由页面调用 notifier。
class ActiveWorkoutToolRow extends StatelessWidget {
  /// 是否显示「上一组」
  final bool showPrevSet;

  /// 是否处于自动（计时）模式
  final bool isAutoMode;

  /// 是否处于休息倒计时
  final bool isResting;

  /// 语音播报是否开启
  final bool voiceEnabled;

  /// 休息时长（秒）
  final int restDurationSec;

  /// 训练时长（秒）
  final int trainingDurationSec;

  /// 节拍间隔（秒）
  final int paceIntervalSec;

  final VoidCallback onPrevSet;
  final VoidCallback onStartTraining;
  final VoidCallback onStopTimer;
  final VoidCallback onToggleRest;
  final VoidCallback onEditTrainingTime;
  final VoidCallback onEditRestTime;
  final VoidCallback onCyclePace;
  final VoidCallback onToggleVoice;

  const ActiveWorkoutToolRow({
    super.key,
    required this.showPrevSet,
    required this.isAutoMode,
    required this.isResting,
    required this.voiceEnabled,
    required this.restDurationSec,
    required this.trainingDurationSec,
    required this.paceIntervalSec,
    required this.onPrevSet,
    required this.onStartTraining,
    required this.onStopTimer,
    required this.onToggleRest,
    required this.onEditTrainingTime,
    required this.onEditRestTime,
    required this.onCyclePace,
    required this.onToggleVoice,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: _buildChips()),
      ),
    );
  }

  List<Widget> _buildChips() {
    final chips = <Widget>[];

    if (showPrevSet && !isAutoMode) {
      chips.add(_chip('上一组', Icons.undo, onPrevSet));
    }

    if (isAutoMode) {
      chips.add(_chip('停止计时', Icons.stop_circle_outlined, onStopTimer,
          highlighted: true));
    } else if (!isResting) {
      chips.add(_chip('计时训练', Icons.play_circle_outline, onStartTraining));
    }

    chips.add(
      _chip(
        isResting ? '停止休息' : '开始休息 ${restDurationSec}s',
        isResting ? Icons.timer_off : Icons.timer_outlined,
        onToggleRest,
        highlighted: isResting,
      ),
    );
    chips.add(_chip('训练 ${trainingDurationSec}s', Icons.fitness_center,
        onEditTrainingTime));
    chips.add(_chip('休息 ${restDurationSec}s', Icons.timelapse, onEditRestTime));
    chips.add(_chip('节拍 ${paceIntervalSec}s', Icons.graphic_eq, onCyclePace));
    chips.add(
      _chip(
        voiceEnabled ? '语音开' : '语音关',
        voiceEnabled ? Icons.volume_up : Icons.volume_off,
        onToggleVoice,
        highlighted: voiceEnabled,
      ),
    );

    return chips;
  }

  /// 单个工具胶囊
  Widget _chip(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool highlighted = false,
  }) {
    final color =
        highlighted ? ActiveWorkoutStyle.green : ActiveWorkoutStyle.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(ActiveWorkoutStyle.controlRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(ActiveWorkoutStyle.controlRadius),
            border: Border.all(
              color: highlighted
                  ? ActiveWorkoutStyle.green.withAlpha(90)
                  : ActiveWorkoutStyle.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
