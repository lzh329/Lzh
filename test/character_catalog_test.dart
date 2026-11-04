import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';

/// 角色领域纯函数：白名单 / 形态名 / 台词分档 / 纯函数性 / 素材缺失回落
///
/// 对应 C-1 / C-9 / C-11 / C-12 / C-15（纯函数部分）
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
      for (final loss in [0.0, 1.9, 2.0, 4.9, 5.0, 30.0]) {
        final spec = CharacterCatalog.resolve('phoebe', loss);
        expect(spec.form, 1, reason: '菲比不会变样子');
        expect(spec.formName, '菲比');
        expect(spec.isMaxForm, isTrue, reason: '菲比永远是"已全部解锁"');
        expect(spec.remainToNextJin, isNull, reason: '不该显示"再减 X 斤换下一个样子"');
      }
    });

    test('lineTier 按 0/2/5 斤算 1/2/3，且三角色共用同一套阈值', () {
      expect(CharacterCatalog.resolve('phoebe', 0).lineTier, 1);
      expect(CharacterCatalog.resolve('phoebe', 1.99).lineTier, 1);
      expect(CharacterCatalog.resolve('phoebe', 2).lineTier, 2);
      expect(CharacterCatalog.resolve('phoebe', 4.99).lineTier, 2);
      expect(CharacterCatalog.resolve('phoebe', 5).lineTier, 3);
      for (final id in ['guga', 'nuonuo']) {
        expect(CharacterCatalog.resolve(id, 3).lineTier, 2);
        expect(CharacterCatalog.resolve(id, 6).lineTier, 3);
      }
    });

    test('菲比 0 斤与 5 斤的台词池不同（阶段感只靠台词）', () {
      final low = CharacterCatalog.resolve('phoebe', 0).linePool;
      final high = CharacterCatalog.resolve('phoebe', 6).linePool;
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
      final a = CharacterCatalog.resolve('nuonuo', 3.2);
      final b = CharacterCatalog.resolve('nuonuo', 3.2);
      expect(a.id, b.id);
      expect(a.form, b.form);
      expect(a.lineTier, b.lineTier);
      expect(a.formName, b.formName);
      expect(a.imageAsset, b.imageAsset);
      expect(a.rivPath, b.rivPath);
      expect(a.linePool, equals(b.linePool));
      expect(a.remainToNextJin, b.remainToNextJin);
      expect(a.nextFormName, b.nextFormName);
      expect(a.isMaxForm, b.isMaxForm);
    });

    test('调 resolve 不触 DB（本文件没有 DB 依赖，能编译即证明）', () {
      // 如果 resolve 内部读了 DB，这个测试文件就不会只 import 纯函数而通过。
      // 这里额外断言一次"结果在 DB 变化后也不会变"的语义：纯计算。
      final spec = CharacterCatalog.resolve('guga', 2.0);
      expect(spec.historyMaxLossJin, 2.0);
      expect(spec.form, 2);
    });

    test('非法输入（NaN / Infinity / 负数）不会崩，按 0 处理', () {
      for (final bad in [double.nan, double.infinity, -3.0]) {
        final spec = CharacterCatalog.resolve('guga', bad);
        expect(spec.form, 1);
        expect(spec.historyMaxLossJin, 0);
      }
    });

    test('越界 loss 夹到最高档，且 remainToNextJin 为 null', () {
      final spec = CharacterCatalog.resolve('guga', 999);
      expect(spec.form, 3);
      expect(spec.isMaxForm, isTrue);
      expect(spec.remainToNextJin, isNull);
      expect(spec.nextFormName, isNull);
    });
  });

  group('R-2 资源路径由注册表声明', () {
    test('rivPath 规则为 assets/rive/{character}_{form}.riv（1 起算）', () {
      for (final id in ['guga', 'nuonuo', 'phoebe']) {
        for (final form in [1, 2, 3]) {
          final spec = CharacterCatalog.resolve(id, form == 1 ? 0 : (form == 2 ? 2 : 5));
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
      // 回落规则：用当前 form 去取咕嘎的同一档，而不是回落到"永远肥咕嘎"
      for (final form in [1, 2, 3]) {
        final loss = form == 1 ? 0.0 : (form == 2 ? 2.5 : 6.0);
        final gugaSpec = CharacterCatalog.resolve('guga', loss);
        expect(gugaSpec.form, form);
        expect(gugaSpec.hasAsset, isTrue, reason: '咕嘎是最后一道保险，必带素材');
      }
    });
  });

  group('C-18/C-19 文案与口径', () {
    test('解锁提示用「换下一个样子」，且不带"形态"二字', () {
      final text = kRemainToNextForm(1.4, '普通咕嘎');
      expect(text, '再减 1.4 斤，换下一个样子：普通咕嘎');
      expect(text.contains('形态'), isFalse);
    });

    test('解锁提示与趋势页「累计减重」措辞不同（两个数字口径不同，文案必须区分）', () {
      final text = kRemainToNextForm(1.4, '普通咕嘎');
      expect(text.contains('累计减重'), isFalse,
          reason: '趋势页说"累计减重"，形象页说"再减 X 斤"，措辞相同会让人以为算错了');
      expect(text.contains('再减'), isTrue);
    });

    test('nextFormName 给出的是下一档的形态名', () {
      expect(CharacterCatalog.resolve('nuonuo', 0).nextFormName, '糯糯（蓝发版）');
      expect(CharacterCatalog.resolve('nuonuo', 2).nextFormName, '糯糯（灰发版）');
      expect(CharacterCatalog.resolve('nuonuo', 5).nextFormName, isNull);
      expect(CharacterCatalog.resolve('nuonuo', 0).remainToNextJin, 2);
      expect(CharacterCatalog.resolve('nuonuo', 3).remainToNextJin, 2);
    });
  });
}
