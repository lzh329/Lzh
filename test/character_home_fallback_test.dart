import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'fake_database.dart';

/// C-15（层 2）当前角色素材缺失 → **首页回落咕嘎同形态**
///
/// PRD §6.1 原文：「当前角色的 PNG 缺失或损坏 → 形象页该卡「素材缺失」不可选；
/// 如果它是当前选中项 → 首页回落**咕嘎同形态**图」。
///
/// 两个必须守住的点：
/// ① 回落的是**图**，不是图标占位（层 3 只在咕嘎也缺时才出现）；
/// ② 回落**不换档**：糯糯第 2 档缺图 → 咕嘎第 2 档，而不是"按减重重新算"。
void main() {
  /// 咕嘎 3 档的 6 张图都在，糯糯/菲比一张都不在（模拟"新角色抠图没跟进包"）
  const gugaOnly = <String>{
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

  /// 起始 70 斤 → 最低 67.5 斤 ⇒ 历史最大减重 2.5 斤 ⇒ 第 2 档
  const weights = [70.0, 67.5];

  group('回落规格本身（纯函数）', () {
    test('糯糯第 2 档缺图 → 咕嘎第 2 档（同档，不跳档）', () {
      final nuonuo = CharacterCatalog.resolve('nuonuo', 2.5);
      expect(nuonuo.form, 2);

      final fallback =
          CharacterCatalog.specOfForm(CharacterId.guga, nuonuo.form, 2.5);
      expect(fallback.id, CharacterId.guga);
      expect(fallback.form, 2, reason: '回落不换档');
      expect(fallback.formName, '普通咕嘎');
      expect(fallback.imageAsset, 'assets/guga3d/guga_normal.png');
      expect(fallback.headAsset, 'assets/guga3d/guga_normal_head.png');
      expect(fallback.bodyAsset, 'assets/guga3d/guga_normal_body.png');
      expect(fallback.rivPath, 'assets/rive/guga_2.riv');
      // 解锁提示也要对得上：第 2 档 → 距第 3 档（5 斤）还差 2.5 斤
      expect(fallback.remainToNextJin, 2.5);
      expect(fallback.nextFormName, '小咕嘎');
    });

    test('菲比（恒 1 档）缺图 → 咕嘎第 1 档（不因为减重 6 斤就跳到第 3 档）', () {
      final phoebe = CharacterCatalog.resolve('phoebe', 6);
      expect(phoebe.form, 1);

      final fallback =
          CharacterCatalog.specOfForm(CharacterId.guga, phoebe.form, 6);
      expect(fallback.form, 1);
      expect(fallback.formName, '肥咕嘎');
      expect(fallback.isMaxForm, isFalse, reason: '咕嘎还有两档没解锁');
    });

    test('越界档位被夹到合法区间（永不抛）', () {
      for (final form in [0, -3, 9]) {
        final spec = CharacterCatalog.specOfForm(CharacterId.guga, form, 0);
        expect(spec.form, inInclusiveRange(1, 3));
      }
    });
  });

  group('provider：素材缺失时 currentCharacterProvider 回落', () {
    ProviderContainer container({
      required String characterId,
      required Set<String> assets,
    }) {
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
      return c;
    }

    test('选了糯糯但她的图不在包里 → 渲染咕嘎第 2 档的资产', () async {
      final c = container(characterId: 'nuonuo', assets: gugaOnly);
      // 等两个 FutureProvider 都就绪
      await c.read(userSettingsProvider.future);
      await c.read(bodyWeightsJinProvider.future);
      await c.read(characterAssetManifestProvider.future);

      final spec = c.read(currentCharacterProvider);
      expect(spec.id, CharacterId.guga, reason: '图缺失就必须换成咕嘎');
      expect(spec.form, 2);
      expect(spec.imageAsset, 'assets/guga3d/guga_normal.png');
      expect(spec.headAsset, 'assets/guga3d/guga_normal_head.png');
    });

    test('正向对照：图都在包里 → 仍然是糯糯（不误判）', () async {
      final c = container(characterId: 'nuonuo', assets: {
        ...gugaOnly,
        'assets/characters/nuonuo_1.png',
        'assets/characters/nuonuo_2.png',
        'assets/characters/nuonuo_3.png',
        'assets/characters/phoebe_1.png',
      });
      await c.read(userSettingsProvider.future);
      await c.read(bodyWeightsJinProvider.future);
      await c.read(characterAssetManifestProvider.future);

      final spec = c.read(currentCharacterProvider);
      expect(spec.id, CharacterId.nuonuo);
      expect(spec.form, 2);
      expect(spec.imageAsset, 'assets/characters/nuonuo_2.png');
    });

    test('分层角色只缺一半（有头没身体）也算缺失', () async {
      // 咕嘎当前选中，但 body 不在清单里
      final c = container(
        characterId: 'guga',
        assets: gugaOnly
            .where((a) => a != 'assets/guga3d/guga_normal_body.png')
            .toSet(),
      );
      await c.read(userSettingsProvider.future);
      await c.read(bodyWeightsJinProvider.future);
      await c.read(characterAssetManifestProvider.future);

      final spec = c.read(currentCharacterProvider);
      // 咕嘎自己缺 → 回落目标也是咕嘎（同图）；manifest 判断仍然走"缺"分支，
      // 但不能因此崩或抛：最终规格仍是咕嘎第 2 档，层 3（errorBuilder）兜底显示图标。
      expect(spec.id, CharacterId.guga);
      expect(spec.form, 2);
    });
  });

  group('widget：首页渲染的是 guga_2 的**图**，不是图标占位', () {
    testWidgets('糯糯缺图 → CharacterView 画出 guga_normal_head/body 两张图', (tester) async {
      final db = fakeDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userSettingsProvider.overrideWith((ref) async =>
              const UserSettingsEntity(id: 1, characterId: 'nuonuo')),
          bodyWeightsJinProvider.overrideWith((ref) async => weights),
          characterAssetManifestProvider
              .overrideWith((ref) async => gugaOnly),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Consumer(
                builder: (context, ref, _) {
                  final spec = ref.watch(currentCharacterProvider);
                  return CharacterView(
                    spec: spec,
                    height: 150,
                    line: '在的',
                    // 本期没有 .riv，强制程序化（等效于真实运行时的默认路径）
                    forceProcedural: true,
                  );
                },
              ),
            ),
          ),
        ),
      ));
      // 三轮：settings → manifest → 重建
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final assets = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => (i.image as AssetImage).assetName)
          .toList();

      expect(assets, hasLength(2), reason: '咕嘎是分层角色：头 + 身体');
      expect(assets, containsAll([
        'assets/guga3d/guga_normal_head.png',
        'assets/guga3d/guga_normal_body.png',
      ]));
      expect(assets.any((a) => a.contains('nuonuo')), isFalse,
          reason: '糯糯的图不在包里，不该被引用');
      expect(find.byIcon(Icons.sentiment_satisfied_alt), findsNothing,
          reason: '层 3 的图标占位只在咕嘎也缺图时出现');
    });
  });
}
