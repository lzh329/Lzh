import 'package:flutter/material.dart';

import 'template_edit_item.dart';

/// 「调整组数/次数」对话框
///
/// 抽成独立函数（不是 widget）的原因：它只负责收集三个数字并返回**新值**，
/// 由页面决定怎么写回自己的 state —— 这样页面里不需要再摆一段 60 行的
/// AlertDialog 构建逻辑，行数留给布局。
Future<EditItem?> showExerciseItemEditor(
  BuildContext context, {
  required EditItem item,
}) async {
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
