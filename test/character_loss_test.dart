import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_loss.dart';

/// 减重口径：**只用于展示**（趋势页「累计减重」等文案与数据），
/// 不再决定形态 —— 形态由累计打卡天数决定（见 character_form_checkin_test.dart）。
///
/// 对应 C-7 的边界表（0 条 / 1 条 / 涨了 / 删最低点）
void main() {
  group('C-7 历史最大减重口径（纯展示）', () {
    test('60 → 58 → 59 → 58.5：min/current/historyMax 各就各位', () {
      final snap = CharacterLoss.of([60.0, 58.0, 59.0, 58.5]);
      expect(snap.startJin, 60);
      expect(snap.minJin, 58);
      expect(snap.currentJin, 58.5);
      expect(snap.historyMaxLossJin, 2.0);

      // 展示口径（趋势页）用 current：60 - 58.5 = 1.5
      expect(snap.currentLossJin, 1.5);

      // 又录一条 59（涨回去了）：历史最大减重仍按最低点 58 算
      final after = CharacterLoss.of([60.0, 58.0, 59.0, 58.5, 59.0]);
      expect(after.historyMaxLossJin, 2.0);
      expect(after.currentLossJin, 1.0,
          reason: '展示口径会变小，这是事实陈述，不是形态回退');
    });
  });

  group('边界：没数据 / 一条数据 / 体重涨了', () {
    test('0 条记录：两个 loss = 0，不出现 NaN', () {
      final snap = CharacterLoss.of(const []);
      expect(snap.startJin, isNull);
      expect(snap.minJin, isNull);
      expect(snap.currentJin, isNull);
      expect(snap.historyMaxLossJin, 0);
      expect(snap.currentLossJin, 0);
    });

    test('只有 1 条记录：start == min == current，两个 loss = 0', () {
      final snap = CharacterLoss.of([70.0]);
      expect(snap.startJin, 70);
      expect(snap.minJin, 70);
      expect(snap.currentJin, 70);
      expect(snap.historyMaxLossJin, 0);
      expect(snap.currentLossJin, 0);
    });

    test('体重涨了（减重为负）：historyMaxLossJin clamp 到 0，不出现负数', () {
      final snap = CharacterLoss.of([60.0, 61.5]);
      expect(snap.historyMaxLossJin, 0, reason: '涨了就是"还没减"，不是负数');
      expect(snap.currentLossJin, -1.5, reason: '展示口径保留符号，供趋势页说"上升"');
    });

    test('删掉最低点那条记录：历史最大减重跟着变（自愈）', () {
      final before = CharacterLoss.of([60.0, 57.0, 58.0]);
      expect(before.historyMaxLossJin, 3.0);

      final after = CharacterLoss.of([60.0, 58.0]);
      expect(after.historyMaxLossJin, 2.0);

      final afterMore = CharacterLoss.of([60.0, 59.0]);
      expect(afterMore.historyMaxLossJin, 1.0);
    });

    test('数据里混入 NaN/Infinity 时不崩（外部损坏数据）', () {
      final snap = CharacterLoss.of([60.0, double.nan, 58.0, double.infinity]);
      expect(snap.startJin, 60);
      expect(snap.minJin, 58);
      expect(snap.historyMaxLossJin, 2.0);
    });

    test('全部是坏数据时退化为"没数据"', () {
      final snap = CharacterLoss.of([double.nan]);
      expect(snap.startJin, isNull);
      expect(snap.historyMaxLossJin, 0);
    });
  });
}
