import 'package:flutter/material.dart';

import 'template_edit_item.dart';

/// 「编辑动作」对话框
///
/// **形态由动作自身的分类决定**，不由模板类型决定：
/// - `cardio`（有氧）→ 组数 + 时长（分钟）
/// - `stretch` 或本身带默认时长（平板支撑这类静力）→ 组数 + 秒
/// - 其余力量动作 → 组数 + 次数
///
/// 同一个模板里可以混着放三类动作（深蹲 3×15 + 跳绳 3×5 分钟），
/// 所以这里必须看每一行动作自己的 `category`，而不是整页的一个开关。
Future<EditItem?> showExerciseItemEditor(
  BuildContext context, {
  required EditItem item,
}) async {
  final mode = _EditorMode.of(item);
  final setsCtrl = TextEditingController(text: '${item.sets}');
  final repsCtrl = TextEditingController(text: item.reps?.toString() ?? '');
  // 有氧按分钟展示，静力按秒展示 —— 单位不同，初值也要各自换算
  final seconds = item.durationSec ?? 0;
  final isTimed = mode != _EditorMode.reps;
  // 计时类动作可以在「分 / 秒」之间切换：有氧默认分、拉伸/静力默认秒
  var useSeconds = mode == _EditorMode.seconds;
  final valueCtrl = TextEditingController(
    text: mode == _EditorMode.cardioMinutes
        ? '${(seconds / 60).round()}'
        : (mode == _EditorMode.seconds ? '$seconds' : ''),
  );

  final result = await showDialog<EditItem>(
    context: context,
    builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
      title: Text('${item.name} · ${mode.label}'),
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
          if (isTimed) ...[
            Row(
              children: [
                const Text('单位', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                for (final unit in const ['分', '秒'])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(unit, style: const TextStyle(fontSize: 11)),
                      selected: (unit == '秒') == useSeconds,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setLocal(() {
                        final toSeconds = unit == '秒';
                        if (toSeconds == useSeconds) return;
                        // 切换单位时保留"真实时长"：先按旧单位解析，再换算显示
                        final v = int.tryParse(valueCtrl.text);
                        final secs = v == null
                            ? seconds
                            : (useSeconds ? v : v * 60);
                        useSeconds = toSeconds;
                        valueCtrl.text = toSeconds
                            ? '$secs'
                            : '${(secs / 60).round()}';
                      }),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: mode == _EditorMode.reps ? repsCtrl : valueCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: mode == _EditorMode.reps
                  ? mode.fieldLabel
                  : (useSeconds ? '每组时长（秒）' : '每组时长（分钟）'),
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
            final sets =
                (int.tryParse(setsCtrl.text) ?? item.sets).clamp(1, 20);
            final raw = int.tryParse(valueCtrl.text);
            Navigator.pop(
              ctx,
              switch (mode) {
                _EditorMode.reps => item.copyWith(
                    sets: sets,
                    reps: int.tryParse(repsCtrl.text) ?? item.reps,
                    durationSec: null,
                  ),
                _EditorMode.cardioMinutes || _EditorMode.seconds =>
                  item.copyWith(
                    sets: sets,
                    reps: null,
                    // 一律落秒：分 -> ×60；秒 -> 原值
                    durationSec:
                        raw == null ? item.durationSec : (useSeconds ? raw : cardioSeconds(raw)),
                  ),
              },
            );
          },
          child: const Text('确定'),
        ),
      ],
        ),
    ),
  );
  return result;
}

/// 三种表单形态
enum _EditorMode {
  reps,
  cardioMinutes,
  seconds;

  static _EditorMode of(EditItem item) {
    if (item.isCardio) return _EditorMode.cardioMinutes;
    // 拉伸本身没有"次数"；静力动作（平板支撑）也没次数 —— 都按时长填
    if (item.category == 'stretch' || item.reps == null) {
      return _EditorMode.seconds;
    }
    return _EditorMode.reps;
  }

  String get label => switch (this) {
        _EditorMode.reps => '力量',
        _EditorMode.cardioMinutes => '有氧',
        _EditorMode.seconds => '计时',
      };

  String get fieldLabel => switch (this) {
        _EditorMode.reps => '每组次数',
        _EditorMode.cardioMinutes => '时长（分钟）',
        _EditorMode.seconds => '每组时长（秒）',
      };
}
