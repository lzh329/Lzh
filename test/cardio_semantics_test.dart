import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 计量方式由**动作分类**决定（不是模板类型）+ 模板类型自动派生
void main() {
  group('deriveTemplateType：模板类型由动作构成派生', () {
    test('纯力量 → strength', () {
      expect(deriveTemplateType(['strength', 'strength']), 'strength');
    });

    test('含一个有氧动作 → cardio（混排也算有氧）', () {
      expect(deriveTemplateType(['strength', 'cardio']), 'cardio');
      expect(deriveTemplateType(['cardio']), 'cardio');
    });

    test('空模板 / 只有拉伸 → strength', () {
      expect(deriveTemplateType(const []), 'strength');
      expect(deriveTemplateType(['stretch']), 'strength');
    });
  });

  group('EditItem.detail：按类别展示（有氧用分钟、静力用秒）', () {
    EditItem item({
      required String category,
      int sets = 3,
      int? reps,
      int? durationSec,
    }) =>
        EditItem(
          exerciseId: 1,
          name: 'x',
          category: category,
          sets: sets,
          reps: reps,
          durationSec: durationSec,
        );

    test('力量：3 × 12', () {
      expect(item(category: 'strength', reps: 12).detail, '3 × 12');
    });

    test('有氧：3 × 5 分钟（不是 300 秒）', () {
      expect(
        item(category: 'cardio', reps: null, durationSec: 300).detail,
        '3 × 5 分钟',
      );
    });

    test('静力/拉伸：3 × 30 秒', () {
      expect(
        item(category: 'stretch', reps: null, durationSec: 30).detail,
        '3 × 30 秒',
      );
      expect(
        item(category: 'strength', reps: null, durationSec: 60).detail,
        '3 × 60 秒',
      );
    });
  });

  test('cardioSeconds：分钟 → 秒', () {
    expect(cardioSeconds(5), 300);
    expect(cardioSeconds(15), 900);
  });
}
