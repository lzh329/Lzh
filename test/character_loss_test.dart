import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_loss.dart';

/// 减重口径：形态按「历史最大减重」，只升不降。
///
/// 对应 C-7 + PRD 8.x 的边界表（0 条 / 1 条 / 涨了 / 删最低点）
void main() {
  group('C-7 历史最大减重口径', () {
    test('60 → 58 → 59 → 58.5：form = 2，再录 59 仍是 2', () {
      final snap = CharacterLoss.of([60.0, 58.0, 59.0, 58.5]);
      expect(snap.startJin, 60);
      expect(snap.minJin, 58);
      expect(snap.currentJin, 58.5);
      expect(snap.historyMaxLossJin, 2.0);

      // 展示口径（趋势页）用 current：60 - 58.5 = 1.5
      expect(snap.currentLossJin, 1.5);

      final spec = CharacterCatalog.resolve('guga', snap.historyMaxLossJin);
      expect(spec.form, 2, reason: '按最低点 58 算 = 减 2 斤 → 第 2 档');

      // 又录一条 59（涨回去了）：形态不回退
      final after = CharacterLoss.of([60.0, 58.0, 59.0, 58.5, 59.0]);
      expect(after.historyMaxLossJin, 2.0);
      expect(CharacterCatalog.resolve('guga', after.historyMaxLossJin).form, 2);
      expect(after.currentLossJin, 1.0,
          reason: '展示口径会变小，这是事实陈述，不是形态回退');
    });

    test('阈值边界：0 / 2 / 5 斤 → form 1 / 2 / 3', () {
      expect(CharacterCatalog.resolve('guga', 0).form, 1);
      expect(CharacterCatalog.resolve('guga', 1.99).form, 2 - 1);
      expect(CharacterCatalog.resolve('guga', 2).form, 2);
      expect(CharacterCatalog.resolve('guga', 4.99).form, 2);
      expect(CharacterCatalog.resolve('guga', 5).form, 3);
      expect(CharacterCatalog.resolve('guga', 50).form, 3);
    });
  });

  group('边界：没数据 / 一条数据 / 体重涨了', () {
    test('0 条记录：两个 loss = 0，form 1，不出现 NaN', () {
      final snap = CharacterLoss.of(const []);
      expect(snap.startJin, isNull);
      expect(snap.minJin, isNull);
      expect(snap.currentJin, isNull);
      expect(snap.historyMaxLossJin, 0);
      expect(snap.currentLossJin, 0);

      final spec = CharacterCatalog.resolve(null, snap.historyMaxLossJin);
      expect(spec.form, 1);
      expect(spec.remainToNextJin, 2.0, reason: '还差 2 斤换下一个样子');
      expect(spec.remainToNextJin!.isNaN, isFalse);
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
      expect(CharacterCatalog.resolve('guga', snap.historyMaxLossJin).form, 1);
    });

    test('删掉最低点那条记录：形态允许回退（自愈，不做补偿）', () {
      final before = CharacterLoss.of([60.0, 57.0, 58.0]);
      expect(before.historyMaxLossJin, 3.0);
      expect(CharacterCatalog.resolve('guga', before.historyMaxLossJin).form, 2);

      // 用户删掉了 57 那条
      final after = CharacterLoss.of([60.0, 58.0]);
      expect(after.historyMaxLossJin, 2.0);
      expect(CharacterCatalog.resolve('guga', after.historyMaxLossJin).form, 2,
          reason: '2 斤仍是第 2 档');

      final afterMore = CharacterLoss.of([60.0, 59.0]);
      expect(CharacterCatalog.resolve('guga', afterMore.historyMaxLossJin).form, 1,
          reason: '删到只剩 1 斤，回退到第 1 档 —— 允许，自愈');
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
