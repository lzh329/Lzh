import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';

/// 角色领域纯函数：白名单 / 形态名 / 台词分档 / 纯函数性 / 素材缺失回落
///
/// 对应 C-1 / C-9 / C-11 / C-12 / C-15（纯函数部分）
/// 形态口径：累计打卡天数 0 / 7 / 21 天（咕嘎、糯糯三档；菲比恒 1）
void main() {
  group('C-1 白名单外 id 全部渲染咕嘎', () {
    const dirty = <String?>[
      'hobby', // 未来版本才有的角色
      '', // 空串（"清除"和"没设"的混用产物）
      null, // 还没建过设置行
      'GUGA', // 大写
      ' guga', // 带空格
      '咕嘎', // 中文
      'nuonuo_v2', // 未来版本的角色
    ];

    for (final raw in dirty) {
      test('resolve(${raw == null ? 'null' : '"$raw"'}) → guga', () {
        final spec = CharacterCatalog.resolve(raw, 0);
        expect(spec.id, CharacterId.guga);
        expect(spec.name, '咕嘎');
        expect(spec.formName, '肥咕嘎');
      });
    }

    test('三个合法值各自解析正确', () {
      expect(CharacterCatalog.resolve('guga', 0).id, CharacterId.guga);
      expect(CharacterCatalog.resolve('nuonuo', 0).id, CharacterId.nuonuo);
      expect(CharacterCatalog.resolve('phoebe', 0).id, CharacterId.phoebe);
    });

    test('CharacterId.parse 永不抛、永不返回 null', () {
      expect(CharacterId.parse(null), CharacterId.guga);
      expect(CharacterId.parse('nope'), CharacterId.guga);
      expect(CharacterId.parse('phoebe'), CharacterId.phoebe);
      expect(CharacterId.tryParse('nope'), isNull);
    });
  });

  group('C-9 形态名只描述外观', () {
    test('咕嘎三档名沿用现值（品牌资产，不改）', () {
      expect(CharacterCatalog.guga.forms.map((f) => f.displayName).toList(),
          ['肥咕嘎', '普通咕嘎', '小咕嘎']);
    });

    test('糯糯三档只描述材质与发色，且不含"肥/小"', () {
      final names =
          CharacterCatalog.nuonuo.forms.map((f) => f.displayName).toList();
      expect(names, ['糯糯（玩偶版）', '糯糯（蓝发版）', '糯糯（灰发版）']);
      for (final n in names) {
        expect(n.contains('肥'), isFalse, reason: '「肥糯糯」听起来是在说用户');
        expect(n.contains('小'), isFalse);
      }
    });

    test('菲比单形象无档名', () {
      expect(CharacterCatalog.phoebe.forms, hasLength(1));
      expect(CharacterCatalog.phoebe.forms.single.displayName, '菲比');
    });

    test('所有形态名都不含禁用词（C10 的第一道闸）', () {
      for (final def in CharacterCatalog.all) {
        for (final form in def.forms) {
          for (final word in kForbiddenFormWords) {
            expect(form.displayName.contains(word), isFalse,
                reason: '${form.displayName} 命中禁用词 $word');
          }
        }
      }
    });
  });

  group('C-11 菲比单形态 + 台词分档', () {
    test('phoebe.forms.length == 1 且 form 恒为 1', () {
      expect(CharacterCatalog.phoebe.forms.length, 1);
      for (final days in [0, 6, 7, 20, 21, 45, 999]) {
        final spec = CharacterCatalog.resolve('phoebe', days);
        expect(spec.form, 1, reason: '菲比不会变样子');
        expect(spec.formName, '菲比');
        expect(spec.isMaxForm, isTrue, reason: '菲比永远是"已全部解锁"');
        expect(spec.remainToNextDays, isNull, reason: '不该显示"再打卡 X 天换下一个样子"');
      }
    });

    test('lineTier 跟形态走：0/7/21 天 → 1/2/3 档', () {
      expect(CharacterCatalog.resolve('guga', 0).lineTier, 1);
      expect(CharacterCatalog.resolve('guga', 6).lineTier, 1);
      expect(CharacterCatalog.resolve('guga', 7).lineTier, 2);
      expect(CharacterCatalog.resolve('guga', 20).lineTier, 2);
      expect(CharacterCatalog.resolve('guga', 21).lineTier, 3);
      expect(CharacterCatalog.resolve('phoebe', 21).lineTier, 1,
          reason: '菲比形态恒 1，台词档也恒 1');
    });

    test('咕嘎不同档的台词池不同（阶段感）', () {
      final low = CharacterCatalog.resolve('guga', 0).linePool;
      final high = CharacterCatalog.resolve('guga', 21).linePool;
      expect(low, isNotEmpty);
      expect(high, isNotEmpty);
      expect(low, isNot(equals(high)));
    });

    test('每档台词 ≥3 句（三角色 × 三档）', () {
      for (final def in CharacterCatalog.all) {
        for (final tier in [1, 2, 3]) {
          expect(def.linesByTier[tier], isNotNull,
              reason: '${def.name} 缺 tier $tier 的台词');
          expect(def.linesByTier[tier]!.length, greaterThanOrEqualTo(3),
              reason: '${def.name} tier $tier 台词不足 3 句，随机轮换会重复');
        }
      }
    });
  });

  group('C-12 resolve 是纯函数', () {
    test('同入参两次调用结果逐字段相等', () {
      final a = CharacterCatalog.resolve('nuonuo', 12);
      final b = CharacterCatalog.resolve('nuonuo', 12);
      expect(a.id, b.id);
      expect(a.form, b.form);
      expect(a.lineTier, b.lineTier);
      expect(a.formName, b.formName);
      expect(a.imageAsset, b.imageAsset);
      expect(a.rivPath, b.rivPath);
      expect(a.linePool, equals(b.linePool));
      expect(a.remainToNextDays, b.remainToNextDays);
      expect(a.nextFormName, b.nextFormName);
      expect(a.isMaxForm, b.isMaxForm);
    });

    test('非法输入（负数）不会崩，按 0 处理', () {
      final spec = CharacterCatalog.resolve('guga', -3);
      expect(spec.form, 1);
      expect(spec.checkinDays, 0);
    });

    test('越界天数夹到最高档，且 remainToNextDays 为 null', () {
      final spec = CharacterCatalog.resolve('guga', 999);
      expect(spec.form, 3);
      expect(spec.isMaxForm, isTrue);
      expect(spec.remainToNextDays, isNull);
      expect(spec.nextFormName, isNull);
    });
  });

  group('R-2 资源路径由注册表声明', () {
    test('rivPath 规则为 assets/rive/{character}_{form}.riv（1 起算）', () {
      const daysByForm = {1: 0, 2: 7, 3: 21};
      for (final id in ['guga', 'nuonuo', 'phoebe']) {
        for (final form in [1, 2, 3]) {
          final spec = CharacterCatalog.resolve(id, daysByForm[form]!);
          expect(spec.rivPath, 'assets/rive/${id}_${spec.form}.riv');
        }
      }
    });

    test('咕嘎走分层（有 _head/_body），糯糯与菲比只有单图', () {
      expect(CharacterCatalog.resolve('guga', 0).hasSplit, isTrue);
      expect(CharacterCatalog.resolve('nuonuo', 0).hasSplit, isFalse);
      expect(CharacterCatalog.resolve('phoebe', 0).hasSplit, isFalse);
      expect(CharacterCatalog.resolve('nuonuo', 0).imageAsset,
          'assets/characters/nuonuo_1.png');
      expect(CharacterCatalog.resolve('phoebe', 0).imageAsset,
          'assets/characters/phoebe_1.png');
    });
  });

  group('C-15（纯函数部分）当前角色素材缺失 → 回落咕嘎同形态', () {
    test('fallback 规格就是咕嘎 1 档', () {
      expect(CharacterCatalog.fallback.id, CharacterId.guga);
      expect(CharacterCatalog.fallback.form, 1);
      expect(CharacterCatalog.fallback.hasSplit, isTrue);
    });

    test('同名形态在同档位一致（首页回落用）', () {
      const daysByForm = {1: 0, 2: 7, 3: 21};
      for (final form in [1, 2, 3]) {
        final gugaSpec = CharacterCatalog.resolve('guga', daysByForm[form]!);
        expect(gugaSpec.form, form);
        expect(gugaSpec.hasAsset, isTrue, reason: '咕嘎是最后一道保险，必带素材');
      }
    });
  });

  group('C-18/C-19 文案与口径', () {
    test('解锁提示用「再打卡 N 天解锁」，且不带"形态"二字', () {
      final text = kRemainToNextForm(9, '普通咕嘎');
      expect(text, '再打卡 9 天解锁「普通咕嘎」');
      expect(text.contains('形态'), isFalse);
    });

    test('解锁提示与趋势页「累计减重」措辞不同', () {
      final text = kRemainToNextForm(9, '普通咕嘎');
      expect(text.contains('累计减重'), isFalse,
          reason: '趋势页说"累计减重"，形象页说"再打卡 X 天"，措辞相同会让人以为算错了');
      expect(text.contains('再打卡'), isTrue);
      expect(text.contains('再减'), isFalse);
    });

    test('nextFormName 给出的是下一档的形态名', () {
      expect(CharacterCatalog.resolve('nuonuo', 0).nextFormName, '糯糯（蓝发版）');
      expect(CharacterCatalog.resolve('nuonuo', 7).nextFormName, '糯糯（灰发版）');
      expect(CharacterCatalog.resolve('nuonuo', 21).nextFormName, isNull);
      expect(CharacterCatalog.resolve('nuonuo', 0).remainToNextDays, 7);
      expect(CharacterCatalog.resolve('nuonuo', 7).remainToNextDays, 14);
    });
  });
}
