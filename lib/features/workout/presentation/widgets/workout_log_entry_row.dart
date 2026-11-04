import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/workout_log_draft.dart';

/// 「记一笔」里的一个动作编辑行：`组 × 次/秒 × 重量`。
///
/// 为什么用 ± 步进而不是输入框：
/// ① 补记发生在训练之后，用户手上有汗、注意力低，键盘弹起会挡住半屏；
/// ② 输入框要为每一行动态创建/销毁 `TextEditingController`，删行时极易漏 dispose
///    （这是列表表单最常见的泄漏）；
/// ③ 训练数据是**离散小整数**（组 1~20、次 1~100、重量 2.5 的倍数），
///    步进比打字更快也更不容易输错。
class WorkoutLogEntryRow extends StatelessWidget {
  final WorkoutLogEntry entry;
  final ValueChanged<WorkoutLogEntry> onChanged;
  final VoidCallback onDelete;

  const WorkoutLogEntryRow({
    super.key,
    required this.entry,
    required this.onChanged,
    required this.onDelete,
  });

  /// 重量步进 2.5kg（健身房最小配重片），0 表示自重
  static const weightStep = 2.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weight = entry.weightKg ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.exerciseName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '删掉这个动作',
                  visualDensity: VisualDensity.compact,
                  color: AppColors.textTertiary,
                  onPressed: onDelete,
                ),
              ],
            ),
            Row(
              children: [
                _Stepper(
                  key: const ValueKey('sets'),
                  label: '组',
                  value: '${entry.sets}',
                  onMinus: () => onChanged(
                      entry.copyWith(sets: (entry.sets - 1).clamp(1, 20))),
                  onPlus: () => onChanged(
                      entry.copyWith(sets: (entry.sets + 1).clamp(1, 20))),
                ),
                const SizedBox(width: 10),
                _Stepper(
                  key: ValueKey(entry.isTimed ? 'seconds' : 'reps'),
                  label: entry.isTimed ? '秒' : '次',
                  value: entry.isTimed
                      ? '${entry.durationSec}'
                      : '${entry.reps ?? 0}',
                  onMinus: () {
                    if (entry.isTimed) {
                      onChanged(entry.copyWith(
                          durationSec:
                              ((entry.durationSec ?? 15) - 15).clamp(15, 3600)));
                    } else {
                      onChanged(entry.copyWith(
                          reps: ((entry.reps ?? 1) - 1).clamp(1, 200)));
                    }
                  },
                  onPlus: () {
                    if (entry.isTimed) {
                      onChanged(entry.copyWith(
                          durationSec:
                              ((entry.durationSec ?? 15) + 15).clamp(15, 3600)));
                    } else {
                      onChanged(entry.copyWith(
                          reps: ((entry.reps ?? 1) + 1).clamp(1, 200)));
                    }
                  },
                ),
                const SizedBox(width: 10),
                _Stepper(
                  key: const ValueKey('weight'),
                  label: 'kg',
                  // 0 = 自重：明确写出来，比显示 "0.0 kg" 更像人话
                  value: weight <= 0 ? '自重' : weight.toStringAsFixed(1),
                  onMinus: () {
                    final next = weight - weightStep;
                    onChanged(next <= 0
                        ? entry.copyWith(clearWeight: true)
                        : entry.copyWith(weightKg: next));
                  },
                  onPlus: () => onChanged(
                      entry.copyWith(weightKg: weight + weightStep)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一个紧凑的 `− 值 +` 步进器（自带单位标签）
class _Stepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _Stepper({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            _StepButton(icon: Icons.remove, onTap: onMinus, tooltip: '减$label'),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9.5, color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            _StepButton(icon: Icons.add, onTap: onPlus, tooltip: '加$label'),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      color: AppColors.primaryText,
      onPressed: onTap,
    );
  }
}
