import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_registry.dart';
import 'package:fittrack/core/services/checkin_days.dart';

void main() {
  group('countCheckinDays', () {
    test('空输入 → 0', () {
      expect(countCheckinDays(const []), 0);
    });

    test('同一天多条记录只算 1 天', () {
      final dates = [
        DateTime(2026, 11, 2, 8),
        DateTime(2026, 11, 2, 20),
        DateTime(2026, 11, 2, 22),
      ];
      expect(countCheckinDays(dates), 1);
    });

    test('跨月连续 3 天 → 3', () {
      final dates = [
        DateTime(2026, 10, 31),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 2),
      ];
      expect(countCheckinDays(dates), 3);
    });

    test('乱序 + 重复去重', () {
      final dates = [
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 3),
        DateTime(2026, 11, 2),
      ];
      expect(countCheckinDays(dates), 3);
    });
  });

  group('formForCheckinDays（按累计打卡天数，0/7/21）', () {
    test('咕嘎三档边界', () {
      const guga = CharacterRegistry.guga;
      expect(guga.formForCheckinDays(0), 1);
      expect(guga.formForCheckinDays(6), 1);
      expect(guga.formForCheckinDays(7), 2);
      expect(guga.formForCheckinDays(20), 2);
      expect(guga.formForCheckinDays(21), 3);
      expect(guga.formForCheckinDays(999), 3); // 只有 3 档，不溢出
      expect(guga.formForCheckinDays(-1), 1); // 负数按 0
    });

    test('糯糯三档边界，999 仍 3 档', () {
      const nuonuo = CharacterRegistry.nuonuo;
      expect(nuonuo.formForCheckinDays(0), 1);
      expect(nuonuo.formForCheckinDays(7), 2);
      expect(nuonuo.formForCheckinDays(21), 3);
      expect(nuonuo.formForCheckinDays(999), 3);
    });

    test('菲比任何天数恒 1 档', () {
      const phoebe = CharacterRegistry.phoebe;
      expect(phoebe.formForCheckinDays(0), 1);
      expect(phoebe.formForCheckinDays(45), 1);
      expect(phoebe.formForCheckinDays(999), 1);
    });
  });

  group('CharacterRenderSpec.resolve（进度文案）', () {
    test('未满档：还差 N 天 + 下一档形态名', () {
      final spec = CharacterCatalog.resolve('guga', 12);
      expect(spec.form, 2);
      expect(spec.formName, '普通咕嘎');
      expect(spec.remainToNextDays, 9); // 21 - 12
      expect(spec.nextFormName, '小咕嘎');
      expect(spec.isMaxForm, isFalse);
    });

    test('满档：已解锁全部，remain 为 null', () {
      final spec = CharacterCatalog.resolve('guga', 21);
      expect(spec.form, 3);
      expect(spec.isMaxForm, isTrue);
      expect(spec.remainToNextDays, isNull);
      expect(spec.nextFormName, isNull);
    });
  });

  group('源码守卫：不再按减重解锁', () {
    test('catalog / registry 不再有减重档位判定', () {
      for (final path in [
        'lib/core/services/character_catalog.dart',
        'lib/core/services/character_registry.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('formForLoss'), isFalse,
            reason: '$path 不应再有 formForLoss');
        expect(src.contains('minLossJin'), isFalse,
            reason: '$path 不应再有 minLossJin');
      }
    });
  });
}
