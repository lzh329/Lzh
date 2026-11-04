import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

import 'fake_database.dart';

/// 冷启动首帧：**已选角色未读到之前，首页不许先画咕嘎**（装机实测问题 1）
///
/// 复现过的现场：覆盖安装后首启，首页顶部是企鹅装咕嘎，而「我的形象」里标的是糯糯；
/// 退出重进才正常。根因是 `userSettingsProvider` 未完成时 `valueOrNull` 为 null，
/// 被当成了"就是咕嘎"，于是先画咕嘎再跳变。
///
/// 修法：`characterResolvedProvider`（设置 hasValue 才算已知）；未已知 → 画**空舞台**
/// （尺寸与角色区一致，所以角色出现时不跳版）。
void main() {
  late AppDatabase db;

  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  Widget home(Completer<UserSettingsEntity?> settings, List<String> assets) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        // 首页数据：空 DashboardData（全字段有默认值），把 IO 都省掉
        dashboardDataProvider.overrideWith((ref) async => const DashboardData()),
        // 设置：**故意挂起**，模拟冷启动时"还没读到"
        userSettingsProvider.overrideWith((ref) => settings.future),
        bodyWeightsJinProvider.overrideWith((ref) async => const <double>[]),
        characterAssetManifestProvider.overrideWith((ref) async => assets.toSet()),
      ],
      child: const MaterialApp(home: DashboardPage()),
    );
  }

  group('首帧不画咕嘎', () {
    testWidgets('设置未读到：不出现任何角色图（空舞台），也不出现咕嘎资产', (tester) async {
      final pending = Completer<UserSettingsEntity?>();
      await tester.pumpWidget(home(pending, const []));
      await tester.pump(); // dashboardData 完成 → 进入 _DashboardBody
      await tester.pump();

      // 角色区还没画：CharacterView 一个都没有
      expect(find.byType(CharacterView), findsNothing,
          reason: '不确定选的是谁，就先空着，不许先画咕嘎再跳变');
      expect(_renderedAssets(tester), isEmpty);
      expect(find.text('咕嘎'), findsNothing);

      // 收尾：把挂起的设置放掉，避免 pending future 泄漏
      pending.complete(const UserSettingsEntity(id: 1));
      await tester.pump();
    });

    testWidgets('设置到达（糯糯）→ 首帧直接是糯糯，**每一帧**都没出现过咕嘎资产', (tester) async {
      final settings = Completer<UserSettingsEntity?>();
      // 逐帧累积：只断言最后一帧会漏掉"中间先画了一帧咕嘎"
      final seen = <String>{};

      await tester.pumpWidget(home(settings, _allCharacterAssets));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
        seen.addAll(_renderedAssets(tester));
      }
      expect(find.byType(CharacterView), findsNothing);

      settings.complete(
          const UserSettingsEntity(id: 1, characterId: 'nuonuo'));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        seen.addAll(_renderedAssets(tester));
      }

      expect(seen, isNotEmpty, reason: '角色区最终要画出来');
      expect(seen.any((a) => a.contains('guga')), isFalse,
          reason: '冷启动从空舞台直接进糯糯，任何一帧都不许出现咕嘎（问题 1）');
      expect(seen.every((a) => a.contains('nuonuo')), isTrue);
    });

    testWidgets('设置到达但没有设置行（新用户）→ 咕嘎（默认角色，允许画）', (tester) async {
      final settings = Completer<UserSettingsEntity?>();
      await tester.pumpWidget(home(settings, _allCharacterAssets));
      await tester.pump();
      await tester.pump();

      settings.complete(null); // 从没设过 → 默认咕嘎
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final assets = _renderedAssets(tester);
      expect(assets.any((a) => a.contains('guga')), isTrue,
          reason: '新用户就该看到咕嘎；这条防止"把默认角色也一起锁住"');
    });
  });
}

/// 收集当前树上所有 `Image.asset` 的资产名
List<String> _renderedAssets(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((i) => i.assetName)
    .toList();

const _allCharacterAssets = <String>[
  'assets/guga3d/guga_fat.png',
  'assets/guga3d/guga_fat_head.png',
  'assets/guga3d/guga_fat_body.png',
  'assets/guga3d/guga_normal.png',
  'assets/guga3d/guga_normal_head.png',
  'assets/guga3d/guga_normal_body.png',
  'assets/guga3d/guga_small.png',
  'assets/guga3d/guga_small_head.png',
  'assets/guga3d/guga_small_body.png',
  'assets/characters/nuonuo_1.png',
  'assets/characters/nuonuo_2.png',
  'assets/characters/nuonuo_3.png',
  'assets/characters/phoebe_1.png',
];
