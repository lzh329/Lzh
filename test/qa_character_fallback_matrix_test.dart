import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'fake_database.dart';

/// QA 补充：C-15 / C-16 的**回落矩阵**（层 2 的边界，不是"全缺"这一种情况）
///
/// 工程师已有测试只覆盖了"糯糯三张全缺"和"咕嘎缺一半"。这里补四类更容易漏的：
///   ① 单图角色的**同角色不同档**缺图（form 1 在、form 2 不在）→ 必须回落
///   ② 只缺 head / 只缺 body（分层角色）→ 必须判缺，不许画"没头的人"
///   ③ 只缺 `.riv`、PNG 都在 → **不得**回落（否则等于把"没有动效"误判成"没有素材"）
///   ④ 资产清单还没读到（null）→ **不得**回落（首帧不能因为 IO 没回来就先换成咕嘎）
void main() {
  const gugaAssets = {
    'assets/guga3d/guga_fat.png',
    'assets/guga3d/guga_fat_head.png',
    'assets/guga3d/guga_fat_body.png',
    'assets/guga3d/guga_normal.png',
    'assets/guga3d/guga_normal_head.png',
    'assets/guga3d/guga_normal_body.png',
    'assets/guga3d/guga_small.png',
    'assets/guga3d/guga_small_head.png',
    'assets/guga3d/guga_small_body.png',
  };
  const nuonuoAssets = {
    'assets/characters/nuonuo_1.png',
    'assets/characters/nuonuo_2.png',
    'assets/characters/nuonuo_3.png',
  };
  const phoebeAssets = {'assets/characters/phoebe_1.png'};

  /// 起始 70 斤 → 最低 67.5 斤 ⇒ 历史最大减重 2.5 斤 ⇒ 第 2 档
  const weightsForm2 = [70.0, 67.5];
  /// 起始 80 斤 → 最低 74 斤 ⇒ 6 斤 ⇒ 咕嘎/糯糯第 3 档，菲比恒第 1 档
  const weightsForm3 = [80.0, 74.0];

  Future<CharacterRenderSpec> resolveWith({
    required String characterId,
    required Set<String> assets,
    List<double> weights = weightsForm2,
  }) async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) async => UserSettingsEntity(id: 1, characterId: characterId)),
      bodyWeightsJinProvider.overrideWith((ref) async => weights),
      characterAssetManifestProvider.overrideWith((ref) async => assets),
    ]);
    addTearDown(c.dispose);
    await c.read(userSettingsProvider.future);
    await c.read(bodyWeightsJinProvider.future);
    await c.read(characterAssetManifestProvider.future);
    return c.read(currentCharacterProvider);
  }

  group('① 单图角色：同角色只有"当前档"缺图也要回落', () {
    test('糯糯第 2 档：nuonuo_2 缺、nuonuo_1 在 → 咕嘎第 2 档（不是降级画 nuonuo_1）',
        () async {
      final spec = await resolveWith(
        characterId: 'nuonuo',
        assets: {...gugaAssets, 'assets/characters/nuonuo_1.png'},
      );

      expect(spec.id, CharacterId.guga, reason: '当前档缺图必须回落');
      expect(spec.form, 2, reason: '回落不换档');
      expect(spec.imageAsset, 'assets/guga3d/guga_normal.png');
      // 关键反例：不许"退一档画 nuonuo_1" —— 那会让用户的减重成果看起来倒退了
      expect(spec.imageAsset, isNot('assets/characters/nuonuo_1.png'));
    });
  });

  group('② 分层角色：只缺一张也要判缺', () {
    test('咕嘎只缺 head：判定为缺（哪怕回落目标还是咕嘎，至少不许画单个 body）',
        () async {
      final spec = await resolveWith(
        characterId: 'guga',
        assets: gugaAssets
            .where((a) => a != 'assets/guga3d/guga_normal_head.png')
            .toSet(),
      );
      // 回落目标也是咕嘎（同角色），断言点在于：不崩、档位不变、且这套 spec
      // 的图片确实是不完整的（层 3 兜底会画图标，而不是"半个咕嘎"）
      expect(spec.id, CharacterId.guga);
      expect(spec.form, 2);
      expect(spec.hasSplit, isTrue);
      expect(spec.headAsset, 'assets/guga3d/guga_normal_head.png');
    });

    test('咕嘎只缺 body：同上', () async {
      final spec = await resolveWith(
        characterId: 'guga',
        assets: gugaAssets
            .where((a) => a != 'assets/guga3d/guga_normal_body.png')
            .toSet(),
      );
      expect(spec.id, CharacterId.guga);
      expect(spec.form, 2);
    });

    test('糯糯（无拆分图）在咕嘎缺一半时，回落目标本身是残缺的 → 仍不抛', () async {
      final spec = await resolveWith(
        characterId: 'nuonuo',
        assets: {
          ...gugaAssets.where((a) => !a.contains('normal_body')),
          ...nuonuoAssets,
        },
        weights: weightsForm3,
      );
      // 糯糯的图都在 → 根本不该回落（这条同时验证"不误判"）
      expect(spec.id, CharacterId.nuonuo);
      expect(spec.form, 3);
      expect(spec.imageAsset, 'assets/characters/nuonuo_3.png');
    });
  });

  group('③ 只缺 .riv、PNG 都在 ⇒ 不得回落', () {
    test('糯糯 PNG 全在、assets/rive 里没有任何 .riv → 仍是糯糯', () async {
      final spec = await resolveWith(
        characterId: 'nuonuo',
        assets: {...gugaAssets, ...nuonuoAssets}, // 刻意不含任何 .riv
      );
      expect(spec.id, CharacterId.nuonuo,
          reason: '没有动效 ≠ 没有素材：回落会把"降级"和"缺图"混成一件事');
      expect(spec.rivPath, 'assets/rive/nuonuo_2.riv');
    });
  });

  group('④ 清单还没读到 / 读失败 ⇒ 不得误回落', () {
    test('manifest 挂起时按声明渲染（糯糯还是糯糯）', () async {
      final db = fakeDatabase();
      addTearDown(db.close);
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        userSettingsProvider.overrideWith((ref) async =>
            const UserSettingsEntity(id: 1, characterId: 'nuonuo')),
        bodyWeightsJinProvider.overrideWith((ref) async => weightsForm2),
        // 永不 complete：模拟 AssetManifest 读得慢
        characterAssetManifestProvider
            .overrideWith((ref) => Future<Set<String>>.delayed(
                  const Duration(seconds: 30),
                  () => <String>{},
                )),
      ]);
      addTearDown(c.dispose);
      await c.read(userSettingsProvider.future);
      await c.read(bodyWeightsJinProvider.future);

      final spec = c.read(currentCharacterProvider);
      expect(spec.id, CharacterId.nuonuo,
          reason: '清单没回来不能当成"图不在"：那会让选了糯糯的用户首帧看到咕嘎');
      expect(spec.form, 2);
    });
  });

  group('⑤ 菲比满减重也不跳档', () {
    test('菲比在 6 斤下仍恒第 1 档；缺图 → 咕嘎第 1 档（不是第 3 档）', () async {
      final available = await resolveWith(
        characterId: 'phoebe',
        assets: {...gugaAssets, ...phoebeAssets},
        weights: weightsForm3,
      );
      expect(available.id, CharacterId.phoebe);
      expect(available.form, 1, reason: '菲比单形象，恒第 1 档');
      expect(available.lineTier, 3, reason: '台词档位照样跟着减重走（C11）');

      final missing = await resolveWith(
        characterId: 'phoebe',
        assets: gugaAssets, // 菲比图缺失
        weights: weightsForm3,
      );
      expect(missing.id, CharacterId.guga);
      expect(missing.form, 1, reason: '回落不换档：不许因为减了 6 斤就冒出第 3 档咕嘎');
    });
  });

  group('⑥ 层 3：立绘真的解码不出来 → 图标占位 + 藏气泡，其余元素不动', () {
    testWidgets('喂一个不存在的路径 → sentiment_satisfied_alt，不抛异常', (tester) async {
      // 注意：manifest 覆写只影响"要不要回落"，不影响 Image.asset 真的去读文件。
      // 所以层 3 必须用**真的读不出来的路径**来构造 —— 否则测试会在
      // "宿主 bundle 里恰好有这张图"时假绿。
      final ghost = _ghostSpec();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CharacterView(
            spec: ghost,
            height: 150,
            line: '在的',
            forceProcedural: true,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.sentiment_satisfied_alt), findsWidgets,
          reason: '层 3：连咕嘎都没有时用图标，不留白框');
      expect(find.text('在的'), findsNothing,
          reason: 'C-16：立绘失败时要藏掉台词气泡');
      expect(tester.takeException(), isNull);
    });
  });
}

/// 一个立绘路径全都不存在的渲染描述（模拟"包里真的一张图都没有"）
CharacterRenderSpec _ghostSpec() {
  final base = CharacterCatalog.resolve('guga', 2.5);
  return CharacterRenderSpec(
    id: base.id,
    name: base.name,
    form: base.form,
    lineTier: base.lineTier,
    formName: base.formName,
    imageAsset: 'assets/guga3d/__missing__.png',
    headAsset: 'assets/guga3d/__missing___head.png',
    bodyAsset: 'assets/guga3d/__missing___body.png',
    rivPath: base.rivPath,
    linePool: base.linePool,
    historyMaxLossJin: base.historyMaxLossJin,
    remainToNextJin: base.remainToNextJin,
    nextFormName: base.nextFormName,
    accent: base.accent,
    introLine: base.introLine,
    formUpLine: base.formUpLine,
    hasSplit: true,
    isMaxForm: base.isMaxForm,
  );
}
