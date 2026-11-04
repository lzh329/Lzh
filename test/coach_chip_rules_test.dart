import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/domain/coach_chip_rules.dart';

/// 芯片规则的回归：证明「无回执 → 无芯片」是设计而不是 bug
///
/// 真机现象：教练说"已帮你补记 11 月 2 日的训练"却没有芯片 —— 根因是模型
/// 根本没调 log_workout（没有回执），不是芯片模块坏了。这里把这条规则锁住。
void main() {
  List<CoachChip> build({
    String text = '',
    List<String> receipts = const [],
  }) =>
      CoachChipRules.build(
        assistantText: text,
        toolReceipts: receipts,
        hasWeightToday: false,
        hasFoodToday: false,
      );

  test('log_workout 成功回执 → 产出 view_workout 且 payload 是 workout_id', () {
    final chips = build(
      text: '训练记录已经补好了',
      receipts: ['log_workout:{"ok":true,"workout_id":42,"date":"2025-11-02"}'],
    );

    final view = chips.where((c) => c.key == 'view_workout');
    expect(view, hasLength(1));
    expect(view.first.payload, '42');
  });

  test('空回执 + 正文声称已补记 → 不产出任何芯片（无回执就无芯片）', () {
    final chips = build(
      text: '已帮你补记 11 月 2 日的训练',
      receipts: const [],
    );
    expect(chips.where((c) => c.key == 'view_workout'), isEmpty);
  });

  test('ok=false 的回执也不产出 view_workout', () {
    final chips = build(
      text: '记录失败了',
      receipts: ['log_workout:{"ok":false}'],
    );
    expect(chips.where((c) => c.key == 'view_workout'), isEmpty);
  });
}
