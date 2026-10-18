import 'package:flutter/material.dart';

/// 首页「今日任务」卡 —— 每日三件事（体重 / 训练 / 饮食）+ 咕嘎陪伴鼓励语
///
/// 设计要点（v2 规范）：
/// - 卡片走全局 CardTheme（#1A1A1A / 圆角 14 / elevation 0）
/// - 卡头图标块使用 color.withAlpha(32) + 圆角 8
/// - 主色绿 #66BB6A，辅助文字 10-11px 走 outline
///
/// 交互说明：三个任务行均可点击；某行未完成且未提供回调时，右侧不展示
/// 「去记录 / 去训练」按钮（仅保留勾选框），避免出现不可用的视觉入口。
class TodayTasksCard extends StatelessWidget {
  /// 今日体重（斤，已 ×2）；null = 今日未记录体重
  final double? todayWeightJin;

  /// 今日训练次数
  final int workoutCount;

  /// 今日摄入热量（kcal）；null = 今日未记录饮食
  final double? calories;

  /// 咕嘎当前形态立绘（null 时鼓励语不展示头像）
  final String? gugaAsset;

  /// 记录体重入口（null = 该入口不可用，隐藏「去记录」）
  final VoidCallback? onTapWeight;

  /// 去训练入口
  final VoidCallback? onTapWorkout;

  /// 记录饮食入口
  final VoidCallback? onTapDiet;

  const TodayTasksCard({
    super.key,
    this.todayWeightJin,
    this.workoutCount = 0,
    this.calories,
    this.gugaAsset,
    this.onTapWeight,
    this.onTapWorkout,
    this.onTapDiet,
  });

  static const _green = Color(0xFF66BB6A);
  static const Color _cardText = Colors.white;
  static const Color _doneText = Colors.white54;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;

    final weightDone = todayWeightJin != null;
    final workoutDone = workoutCount > 0;
    final dietDone = calories != null;

    final doneCount =
        (weightDone ? 1 : 0) + (workoutDone ? 1 : 0) + (dietDone ? 1 : 0);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 卡头：图标块 + 标题 + 完成进度 ──
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _green.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.checklist, size: 15, color: _green),
                ),
                const SizedBox(width: 10),
                Text('今日任务', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '$doneCount/3',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── 任务行 1：记录体重 ──
            _TaskRow(
              label: '记录体重',
              done: weightDone,
              doneValue: weightDone
                  ? '${todayWeightJin!.toStringAsFixed(1)} 斤'
                  : null,
              actionLabel: '去记录',
              onTap: onTapWeight,
              textColor: weightDone ? _doneText : _cardText,
              accentColor: _green,
              valueColor: outline,
            ),

            // ── 任务行 2：完成训练 ──
            _TaskRow(
              label: '完成训练',
              done: workoutDone,
              doneValue: workoutDone ? '$workoutCount 次' : null,
              actionLabel: '去训练',
              onTap: onTapWorkout,
              textColor: workoutDone ? _doneText : _cardText,
              accentColor: _green,
              valueColor: outline,
            ),

            // ── 任务行 3：记录饮食 ──
            _TaskRow(
              label: '记录饮食',
              done: dietDone,
              doneValue: dietDone ? '${calories!.round()} kcal' : null,
              actionLabel: '去记录',
              onTap: onTapDiet,
              textColor: dietDone ? _doneText : _cardText,
              accentColor: _green,
              valueColor: outline,
            ),

            // ── 咕嘎鼓励语 ──
            const SizedBox(height: 10),
            _GugaCheerRow(
              asset: gugaAsset,
              text: _cheerText(doneCount),
              color: _green,
            ),
          ],
        ),
      ),
    );
  }

  /// 按完成项数生成鼓励语
  static String _cheerText(int doneCount) {
    if (doneCount >= 3) return '今日全部完成，咕嘎为你鼓掌！';
    if (doneCount >= 1) return '已经完成 $doneCount 项，继续保持';
    return '先动起来，比什么都重要';
  }
}

/// 单条任务行：勾选框 + 文案 + 右侧完成值 / 行动按钮
class _TaskRow extends StatelessWidget {
  final String label;
  final bool done;

  /// 完成时右侧展示的数值文案（如 `142.0 斤`）
  final String? doneValue;

  /// 未完成时右侧按钮文案（如 `去记录`）
  final String? actionLabel;

  /// 未完成时的点击回调（null 则不展示右侧按钮）
  final VoidCallback? onTap;

  final Color textColor;
  final Color accentColor;
  final Color valueColor;

  const _TaskRow({
    required this.label,
    required this.done,
    required this.textColor,
    required this.accentColor,
    required this.valueColor,
    this.doneValue,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showAction = !done && actionLabel != null && onTap != null;

    return InkWell(
      onTap: done ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            // 方形勾选框
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: done ? accentColor : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: done
                    ? null
                    : Border.all(color: Colors.white.withAlpha(51), width: 1),
              ),
              child: done
                  ? const Icon(Icons.check, size: 12, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (done) ...[
              if (doneValue != null)
                Text(
                  doneValue!,
                  style: TextStyle(fontSize: 11, color: valueColor),
                ),
              const SizedBox(width: 8),
              Icon(Icons.check_circle, size: 18, color: accentColor),
            ] else if (showAction)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withAlpha(26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  actionLabel!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 咕嘎鼓励语行：圆形小头像 + 11px 文案
class _GugaCheerRow extends StatelessWidget {
  final String? asset;
  final String text;
  final Color color;

  const _GugaCheerRow({
    required this.text,
    required this.color,
    this.asset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (asset != null) ...[
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: color.withAlpha(90), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              asset!,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 11, color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
