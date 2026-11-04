import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/workout_repeat.dart';

/// 「再练一次」（T15）。
///
/// 三个刻意的决定：
/// 1. **不预填重量**：上次能做 ≠ 这次能做。预填是"受伤"和"数据造假"
///    （用户一路点完成）两个坑的共同源头。
/// 2. **`pushReplacement`**：练完返回该回记录页，不该回这条记录的详情页 ——
///    用户刚看完这条记录，再回去只会让他以为没开练。
/// 3. **整卡不放按钮**：卡片本身就是"进详情"的热区，再叠一个右向元素
///    会有两个热区打架（决策 11）。
class WorkoutRepeatButton extends ConsumerStatefulWidget {
  final WorkoutEntity workout;

  const WorkoutRepeatButton({super.key, required this.workout});

  @override
  ConsumerState<WorkoutRepeatButton> createState() =>
      _WorkoutRepeatButtonState();
}

class _WorkoutRepeatButtonState extends ConsumerState<WorkoutRepeatButton> {
  bool _busy = false;

  /// 这条记录没有任何 sets ⇒ 按钮置灰（理论不会发生，但别给死按钮）
  bool get _disabled => widget.workout.sets.isEmpty || _busy;

  Future<void> _repeat() async {
    if (_disabled) return;
    setState(() => _busy = true);
    try {
      final exercises = await ref.read(exerciseRepoProvider).getAll();
      final names = {for (final e in exercises) e.id: e.name};
      final categories = {for (final e in exercises) e.id: e.category};
      final slots = WorkoutRepeat.slotsOf(widget.workout, names, categories);
      if (!mounted) return;
      if (slots.isEmpty) return; // 双保险：没有动作明细就不跳
      context.pushReplacement('/workout/active', extra: slots);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.workout.sets.isEmpty
          ? '这条记录没有动作明细'
          : '会把上次的动作和目标组数带过去，重量请重新填',
      child: OutlinedButton.icon(
        onPressed: _disabled ? null : _repeat,
        icon: const Icon(Icons.replay, size: 18),
        label: Text(_busy ? '准备中…' : '再练一次'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          foregroundColor: AppColors.primaryText,
          side: BorderSide(
            color: _disabled ? AppColors.border : AppColors.primary.withAlpha(150),
          ),
        ),
      ),
    );
  }
}
