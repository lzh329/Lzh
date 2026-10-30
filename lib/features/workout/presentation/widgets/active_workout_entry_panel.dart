import 'package:flutter/material.dart';

import 'active_workout_style.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 训练执行页下部紧凑输入区（Keep「训练中」风格）。
///
/// 横向一排名为「次数 / 重量 / 时长」的 dense 输入框，圆角 10，
/// 绑定页面持有的 controller，不读写任何状态。
class ActiveWorkoutEntryPanel extends StatelessWidget {
  /// 动作分类（cardio / stretch / gym / bodyweight ...）
  final String category;

  /// 是否计时类动作（有氧 / 拉伸）
  final bool isTimed;

  /// 是否处于休息倒计时（休息中允许先填下一组）
  final bool isResting;

  /// 当前动作所有组是否已完成（完成后隐藏输入框）
  final bool isLastSet;

  /// 上次输入的次数，作为 hint 预填
  final String? lastReps;

  /// 上次输入的重量，作为 hint 预填
  final String? lastWeight;

  /// 上次输入的时长，作为 hint 预填
  final String? lastDuration;

  /// 动作目标次数
  final int? targetReps;

  /// 动作目标时长
  final int? targetDurationSec;

  /// 动作目标重量
  final double? targetWeightKg;

  final TextEditingController repsController;
  final TextEditingController weightController;
  final TextEditingController durationController;

  /// 工具行（可选；重构后移至训练设置弹层，传入时为内嵌模式）
  final Widget? toolRow;

  const ActiveWorkoutEntryPanel({
    super.key,
    required this.category,
    required this.isTimed,
    this.isResting = false,
    required this.isLastSet,
    required this.lastReps,
    required this.lastWeight,
    required this.lastDuration,
    required this.targetReps,
    required this.targetDurationSec,
    required this.targetWeightKg,
    required this.repsController,
    required this.weightController,
    required this.durationController,
    this.toolRow,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isLastSet) ...[
          if (isResting) ...[
            const Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 12, color: ActiveWorkoutStyle.green),
                SizedBox(width: 4),
                Text(
                  '休息中 · 可以先填下一组',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: ActiveWorkoutStyle.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          _buildInputRow(),
          const SizedBox(height: 8),
        ],
        if (toolRow != null) toolRow!,
      ],
    );
  }

  /// 横向一排行输入框
  Widget _buildInputRow() {
    final fields = <Widget>[];

    // 次数（非有氧动作）
    if (category != 'cardio') {
      fields.add(
        _buildField(
          controller: repsController,
          label: isResting ? '下一组 · 次数' : '次数',
          hint: lastReps ?? '${targetReps ?? 12}',
          suffix: '次',
        ),
      );
    }

    // 重量（器械动作）
    // v23 之后器械与徒手统一是 strength：都可能负重，所以重量输入对所有
    // 力量动作都显示，且保持可选（留空 = 自重）
    if (category == 'strength') {
      fields.add(
        _buildField(
          controller: weightController,
          label: isResting ? '下一组 · 重量' : '重量',
          hint: _numberHint(lastWeight, targetWeightKg),
          suffix: 'kg',
          decimal: true,
        ),
      );
    }

    // 时长（有氧 / 拉伸动作）
    if (isTimed) {
      fields.add(
        _buildField(
          controller: durationController,
          label: isResting ? '下一组 · 时长' : '时长',
          hint: lastDuration ?? '${targetDurationSec ?? 60}',
          suffix: '秒',
        ),
      );
    }

    if (fields.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(child: fields[i]));
    }
    return Row(children: children);
  }

  /// 单个紧凑输入框（上方 10.5px 标签 + 40 高输入框）
  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required String suffix,
    bool decimal = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: ActiveWorkoutStyle.textTertiary,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: TextField(
            controller: controller,
            keyboardType: decimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
            textAlign: TextAlign.center,
            cursorColor: ActiveWorkoutStyle.green,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ActiveWorkoutStyle.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: ActiveWorkoutStyle.inputFill,
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: AppColors.textTertiary,
              ),
              suffixText: suffix,
              suffixStyle: const TextStyle(
                fontSize: 11,
                color: ActiveWorkoutStyle.textTertiary,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: _fieldBorder(ActiveWorkoutStyle.border),
              enabledBorder: _fieldBorder(ActiveWorkoutStyle.border),
              focusedBorder: _fieldBorder(ActiveWorkoutStyle.green),
            ),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _fieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(ActiveWorkoutStyle.controlRadius),
      borderSide: BorderSide(color: color),
    );
  }

  /// 重量 hint：优先上次输入值，其次动作目标重量
  String _numberHint(String? last, double? target) {
    if (last != null && last.isNotEmpty) return last;
    if (target == null) return '60';
    return target % 1 == 0
        ? target.toStringAsFixed(0)
        : target.toStringAsFixed(1);
  }
}
