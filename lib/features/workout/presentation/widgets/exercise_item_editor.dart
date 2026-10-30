import 'package:flutter/material.dart';

import 'template_edit_item.dart';

/// 「调整组数/次数」对话框
///
/// 抽成独立函数（不是 widget）的原因：它只负责收集几个数字并返回**新值**，
/// 由页面决定怎么写回自己的 state —— 这样页面里不需要再摆一段 60 行的
/// AlertDialog 构建逻辑，行数留给布局。
///
/// [isCardio] 决定表单形态：
/// - `false`（力量）：组数 + 次数，静力动作则是组数 + 每组秒数（原行为）
/// - `true`（有氧）：**只有「时长（分钟）」一格** —— 有氧没有"组"和"次"，
///   多摆两格空输入框只会让人以为要填
///
/// 返回值契约两种模式完全一致（`EditItem` 的 sets/reps/durationSec），
/// 有氧固定 `sets=1 / reps=null / durationSec=分钟×60`，调用方无需分支。
Future<EditItem?> showExerciseItemEditor(
  BuildContext context, {
  required EditItem item,
  bool isCardio = false,
}) async {
  if (isCardio) return _showCardio(context, item: item);

  final setsCtrl = TextEditingController(text: '${item.sets}');
  final isTimed = item.reps == null;
  final repsCtrl = TextEditingController(text: item.reps?.toString() ?? '');
  final durCtrl =
      TextEditingController(text: item.durationSec?.toString() ?? '');

  final result = await showDialog<EditItem>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: setsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '组数',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: isTimed ? durCtrl : repsCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: isTimed ? '每组时长（秒）' : '每组次数',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final sets = int.tryParse(setsCtrl.text) ?? item.sets;
            Navigator.pop(
              ctx,
              item.copyWith(
                sets: sets.clamp(1, 20),
                reps:
                    isTimed ? null : (int.tryParse(repsCtrl.text) ?? item.reps),
                durationSec: isTimed
                    ? (int.tryParse(durCtrl.text) ?? item.durationSec)
                    : null,
              ),
            );
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result;
}

/// 有氧版：只有一个「时长（分钟）」输入
///
/// 初值优先级：已有 durationSec → 该动作的默认时长 → 10 分钟。
/// 标题写「编辑动作 · 有氧」，让用户确认自己没点错模板类型。
Future<EditItem?> _showCardio(
  BuildContext context, {
  required EditItem item,
}) async {
  final initialMinutes = item.durationSec != null && item.durationSec! > 0
      ? (item.durationSec! / 60).round()
      : 10;
  final minutesCtrl = TextEditingController(text: '$initialMinutes');

  return showDialog<EditItem>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('编辑动作 · 有氧'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.name,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A8F98))),
          const SizedBox(height: 10),
          TextField(
            controller: minutesCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '时长（分钟）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final minutes = int.tryParse(minutesCtrl.text) ?? initialMinutes;
            final v = cardioItemValues(minutes);
            Navigator.pop(
              ctx,
              item.copyWith(
                sets: v.sets,
                reps: v.reps,
                durationSec: v.durationSec,
              ),
            );
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}
