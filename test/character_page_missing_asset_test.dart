import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/presentation/pages/character_page.dart';

import 'fake_database.dart';

/// C-15 / C-16 素材缺失的三层降级
///
/// 层 1：`.riv` 缺失 → 程序化（见 character_rive_fallback_test）
/// 层 2：当前角色 PNG 缺失 → 形象页该卡「素材缺失」不可选；首页回落咕嘎同形态
/// 层 3：咕嘎也缺失 → 内置图标 + 隐藏台词气泡，首页其余元素不动
void main() {
  late AppDatabase db;
  late UserSettingsRepositoryImpl settings;

  setUp(() {
    db = fakeDatabase();
    settings = UserSettingsRepositoryImpl(db);
  });
  tearDown(() => db.close());

  /// 一个"立绘文件不存在"的角色定义（把路径指到一个不存在的文件名）
  CharacterDef brokenDef(CharacterId id, String name) {
    final base = CharacterCatalog.defOf(id);
    return CharacterDef(
      id: base.id,
      name: name,
      cardTagline: base.cardTagline,
      accent: base.accent,
      forms: [
        for (final f in base.forms)
          CharacterFormSpec(
            form: f.form,
            displayName: f.displayName,
            minLossJin: f.minLossJin,
            imageAsset: 'assets/characters/__missing_${id.wire}.png',
          ),
      ],
      linesByTier: base.linesByTier,
      introLine: base.introLine,
      formUpLine: base.formUpLine,
    );
  }

  Widget page(AppDatabase db) => ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          userSettingsProvider.overrideWith(
              (ref) => UserSettingsRepositoryImpl(db).get()),
        ],
        child: MaterialApp(
          home: CharacterPage(
            catalogOverride: [
              brokenDef(CharacterId.nuonuo, '糯糯'),
            ],
          ),
        ),
      );

  testWidgets('层 2：素材缺失的卡显示「素材缺失」且点击不写库', (tester) async {
    await tester.pumpWidget(page(db));
    await tester.pump(); // 首帧（立绘解码失败 → errorBuilder）
    await tester.pump(); // post-frame → setState(_missing)

    expect(find.text(kMissingAssetPlaceholder), findsOneWidget);

    // 点这张卡：不可选中 ⇒ 不写库
    final before = (await settings.get())?.characterId;
    await tester.tap(find.text('糯糯'));
    await tester.pump();
    expect((await settings.get())?.characterId, before,
        reason: '素材缺失的卡不可选中');
  });

  testWidgets('层 3：咕嘎也缺失 → 内置图标占位 + 隐藏台词气泡', (tester) async {
    // 构造一个"两张图都不存在"的 spec（咕嘎分层图全指向不存在的文件）
    final broken = CharacterCatalog.specOf(
      CharacterDef(
        id: CharacterId.guga,
        name: '咕嘎',
        cardTagline: '',
        accent: CharacterCatalog.guga.accent,
        forms: const [
          CharacterFormSpec(
            form: 1,
            displayName: '肥咕嘎',
            minLossJin: 0,
            headAsset: 'assets/guga3d/__missing_head.png',
            bodyAsset: 'assets/guga3d/__missing_body.png',
          ),
        ],
        linesByTier: const {1: ['在的']},
        introLine: '在的',
      ),
      0,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CharacterView(
            spec: broken,
            height: 150,
            line: '点我聊聊，我在听',
            // 强制程序化：本期没有 .riv，正常也是这条路
            forceProcedural: true,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(); // errorBuilder → post-frame → 藏气泡

    // 图标占位（不是白框）
    expect(find.byIcon(Icons.sentiment_satisfied_alt), findsWidgets);
    // 台词气泡隐藏
    expect(find.text('点我聊聊，我在听'), findsNothing);
  });

  testWidgets('层 2 的正向对照：素材正常时卡片可选中且无「素材缺失」', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        userSettingsProvider.overrideWith(
            (ref) => UserSettingsRepositoryImpl(db).get()),
      ],
      child: const MaterialApp(home: CharacterPage()),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text(kMissingAssetPlaceholder), findsNothing,
        reason: '7 个立绘都在，不该出现占位');
    await tester.tap(find.text('菲比'));
    await tester.pump();
    await tester.pump();
    expect((await settings.get())?.characterId, 'phoebe');
  });

  testWidgets('C-15 首页兜底：当前角色素材缺失时用咕嘎同形态的规格渲染', (tester) async {
    // 纯函数层：同 form 的咕嘎有素材（首页回落的依据）
    final gugaSpec = CharacterCatalog.resolve('guga', 2.5); // form 2
    expect(gugaSpec.form, 2);
    expect(gugaSpec.hasAsset, isTrue);
    // 糯糯同档缺图时，首页用 gugaSpec 渲染；这里断言"咕嘎同形态一定有素材"
    for (final loss in [0.0, 2.5, 6.0]) {
      expect(CharacterCatalog.resolve('guga', loss).hasAsset, isTrue,
          reason: '咕嘎是最后一道保险，任何档位都必须有图');
    }
  });
}
