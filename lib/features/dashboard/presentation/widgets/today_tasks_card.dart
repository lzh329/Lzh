import 'package:flutter/material.dart';

/// 首页「今日任务」卡 —— 首页唯一主区块
///
/// 三件事：记录体重 / 完成训练 / 记录饮食。
/// 训练任务内嵌今日安排（计划排期或推荐模板），可直接开始。
/// 数值只作为任务状态展示（完整统计在「趋势」页）。
class TodayTasksCard extends StatelessWidget {
  /// 今日已记录体重（斤）；未记录为 null
  final double? todayWeightJin;

  /// 当前最新体重（未记录今日时作为参考展示）
  final double? latestWeightJin;

  /// 今日训练标题（如「腿日 · 力量」），无安排为 null
  final String? trainingTitle;

  /// 今日训练摘要（如「3 个动作 · 12 组」）
  final String? trainingSummary;

  /// 有无训练安排（计划或模板）
  final bool hasTraining;

  /// 今日已完成训练次数
  final int workoutCount;

  /// 今日热量（已记录饮食）
  final double? calories;

  /// 咕嘎立绘（鼓励语头像）
  final String? gugaAsset;

  final VoidCallback onWeight;
  final VoidCallback onWorkout;
  final VoidCallback onDiet;

  const TodayTasksCard({
    super.key,
    this.todayWeightJin,
    this.latestWeightJin,
    this.trainingTitle,
    this.trainingSummary,
    this.hasTraining = false,
    this.workoutCount = 0,
    this.calories,
    this.gugaAsset,
    required this.onWeight,
    required this.onWorkout,
    required this.onDiet,
  });

  static const _orange = Color(0xFFFF8A00);
  static const _green = Color(0xFF3DDC84);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final weightDone = todayWeightJin != null;
    final workoutDone = workoutCount > 0;
    final dietDone = calories != null;
    final doneCount = [weightDone, workoutDone, dietDone].where((d) => d).length;

    final encourage = switch (doneCount) {
      0 => '先动起来，比什么都重要',
      1 || 2 => '已经完成 $doneCount 项，继续保持',
      _ => '今日全部完成，咕嘎为你鼓掌！',
    };

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _orange.withAlpha(70), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 卡头：标题 + 完成度 ──
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.checklist, size: 15, color: _orange),
                ),
                const SizedBox(width: 10),
                Text('今日任务', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$doneCount/3',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 1. 记录体重 ──
            _TaskRow(
              done: weightDone,
              title: '记录体重',
              value: weightDone
                  ? '${todayWeightJin!.toStringAsFixed(1)} 斤'
                  : (latestWeightJin != null
                      ? '上次 ${latestWeightJin!.toStringAsFixed(1)} 斤'
                      : '还没有记录'),
              actionLabel: weightDone ? null : '记录',
              onAction: weightDone ? null : onWeight,
              onTap: onWeight,
            ),
            const SizedBox(height: 6),

            // ── 2. 完成训练（内嵌今日安排）──
            _TrainingTaskRow(
              done: workoutDone,
              count: workoutCount,
              title: trainingTitle,
              summary: trainingSummary,
              hasTraining: hasTraining,
              onStart: onWorkout,
            ),
            const SizedBox(height: 6),

            // ── 3. 记录饮食 ──
            _TaskRow(
              done: dietDone,
              title: '记录饮食',
              value: dietDone
                  ? '${calories!.round()} kcal'
                  : '今天还没记录',
              actionLabel: dietDone ? null : '记录',
              onAction: dietDone ? null : onDiet,
              onTap: onDiet,
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.white.withAlpha(12)),
            const SizedBox(height: 10),

            // ── 咕嘎鼓励语 ──
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: gugaAsset != null
                      ? Image.asset(gugaAsset!, fit: BoxFit.cover)
                      : const Icon(Icons.sentiment_satisfied_alt,
                          size: 14, color: _orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    encourage,
                    style: TextStyle(
                      fontSize: 11,
                      color: doneCount == 3 ? _green : Colors.white60,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 普通任务行：勾选框 + 标题 + 状态值 + 右侧动作
class _TaskRow extends StatelessWidget {
  final bool done;
  final String title;
  final String value;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onTap;

  const _TaskRow({
    required this.done,
    required this.title,
    required this.value,
    this.actionLabel,
    this.onAction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            _CheckBox(done: done),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: done ? Colors.white54 : Colors.white,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: done
                    ? theme.colorScheme.outline
                    : const Color(0xFFFF8A00),
                fontWeight: done ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: 6),
              Text(
                '›',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 训练任务行：勾选框 + 标题 + 摘要，右侧「开始」按钮
class _TrainingTaskRow extends StatelessWidget {
  final bool done;
  final int count;
  final String? title;
  final String? summary;
  final bool hasTraining;
  final VoidCallback onStart;

  const _TrainingTaskRow({
    required this.done,
    required this.count,
    required this.title,
    required this.summary,
    required this.hasTraining,
    required this.onStart,
  });

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CheckBox(done: done),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '完成训练',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: done ? Colors.white54 : Colors.white,
                      ),
                    ),
                    if (done) ...[
                      const SizedBox(width: 6),
                      Text(
                        '已练 $count 次',
                        style: const TextStyle(fontSize: 10, color: _orange),
                      ),
                    ],
                  ],
                ),
                if (!done && hasTraining) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (title != null) title!,
                      if (summary != null) summary!,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (!done)
            SizedBox(
              height: 30,
              child: FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                child: Text(hasTraining ? '开始' : '去训练'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final bool done;

  const _CheckBox({required this.done});

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        color: done ? _orange : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: done
            ? null
            : Border.all(color: Colors.white.withAlpha(60), width: 1),
      ),
      child: done
          ? const Icon(Icons.check, size: 12, color: Colors.black)
          : null,
    );
  }
}
