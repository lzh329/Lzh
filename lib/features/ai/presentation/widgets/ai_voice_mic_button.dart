import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 输入栏的麦克风按钮
///
/// 空闲：灰色 `mic_none`；录音中：红色 `mic` + 呼吸光环（由 [pulse] 驱动）。
/// 纯展示组件，听写逻辑在 `AiInputBar` 里，便于单测与复用。
class AiVoiceMicButton extends StatelessWidget {
  final bool listening;
  final bool enabled;
  final Animation<double> pulse;
  final VoidCallback onTap;

  const AiVoiceMicButton({
    super.key,
    required this.listening,
    required this.enabled,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = listening
        ? AppColors.danger
        : (enabled ? AppColors.textSecondary : AppColors.textTertiary);
    final label = listening ? '结束语音输入' : '语音输入';
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          if (listening)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.danger
                    .withAlpha((60 * pulse.value).round().clamp(0, 255)),
              ),
            ),
          child!,
        ],
      ),
      child: IconButton(
        tooltip: label,
        onPressed: enabled ? onTap : null,
        icon: Icon(listening ? Icons.mic : Icons.mic_none,
            size: 22, color: color),
      ),
    );
  }
}
