import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/presentation/pages/character_page.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

import 'fake_database.dart';

/// C-5 / C-6 / C-17（组件与形象页侧）
void main() {
  late _Harness harness;

  setUp(() => harness = _Harness());
  tearDown(() => harness.dispose());

  testWidgets('C-5 换角色即时生效：写库 → invalidate → 就地重建，无「重启」提示',
      (tester) async {
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    // 当前是咕嘎（默认）
    expect(harness.container.read(currentCharacterProvider).id, CharacterId.guga);

    // 点「糯糯」卡（卡片标题是角色名）
    await tester.tap(find.text('糯糯'));
    await tester.pump(); // 写库
    await tester.pump(); // invalidate 后的重建

    expect(harness.container.read(currentCharacterProvider).id,
        CharacterId.nuonuo);
    expect((await harness.settings.get())!.characterId, 'nuonuo');

    // 不许出现"重启后生效"这类提示
    expect(find.textContaining('重启'), findsNothing);
    // 也不许弹确认框
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('C-8 形象页不存在"选形态"控件', (tester) async {
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    // 「形态」是内部术语，用户向只说「样子」（决策 5）
    expect(find.textContaining('形态'), findsNothing);
    // 也不存在任何形态选择器 key
    expect(find.byKey(const ValueKey('form-picker')), findsNothing);
    // 三张卡但只有"选角色"这一个动作
    expect(find.text('咕嘎'), findsOneWidget);
    expect(find.text('糯糯'), findsOneWidget);
    expect(find.text('菲比'), findsOneWidget);
  });

  testWidgets('C-18 形象页：3 张卡 + 当前项勾选 + 「还差 X 斤」状态行', (tester) async {
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    // 描述行**按状态算**：0 斤 → 咕嘎/糯糯都还是第 1 档，「还有 2 个样子等你解锁」
    expect(find.text('还有 2 个样子等你解锁'), findsNWidgets(2),
        reason: '咕嘎 + 糯糯各一句，数字跟着当前档位走');
    // 单形象角色用自己的 tagline，且**不出现"解锁"字样**
    expect(find.text('一直是这个样子，话不多但都在'), findsOneWidget);

    // 当前项有勾选标记
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);

    // 状态行：还有下一档 → 「再减 X 斤，换下一个样子」
    expect(find.textContaining('换下一个样子'), findsWidgets);
    // 菲比只有一个样子 → 不该出现任何"解锁"文案（装机实测问题 2）
    expect(find.textContaining('解锁'), findsWidgets,
        reason: '咕嘎/糯糯的"等你解锁"可以出现');
    expect(find.text('已经全部解锁'), findsNothing,
        reason: '菲比单形象不该说"已全部解锁"');
  });

  testWidgets('C-18 已满档：描述行变「三个样子都解锁了」，不再自相矛盾', (tester) async {
    // 历史最大减重 6 斤 → 咕嘎/糯糯都满档
    await harness.seedWeightLoss(6);
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    // 咕嘎 + 糯糯：「三个样子都解锁了」
    expect(find.text('三个样子都解锁了'), findsNWidgets(2));
    // 同一张卡上不许再出现"等你解锁"（问题 2 的核心）
    expect(find.textContaining('等你解锁'), findsNothing);
    expect(find.textContaining('换下一个样子'), findsNothing);
    // 菲比：仍然只有 tagline，没有解锁字样
    expect(find.text('一直是这个样子，话不多但都在'), findsOneWidget);
    expect(find.text('已经全部解锁'), findsNothing);
  });

  testWidgets('C-18 解锁进度文案随档位变化（第 2 档 → 还有 1 个）', (tester) async {
    // 历史最大减重 2.5 斤 → 第 2 档
    await harness.seedWeightLoss(2.5);
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    expect(find.text('还有 1 个样子等你解锁'), findsNWidgets(2),
        reason: '咕嘎/糯糯都到第 2 档');
    expect(find.textContaining('换下一个样子'), findsWidgets);
  });

  testWidgets('形象页点当前已选角色：无操作（不重复写库）', (tester) async {
    await tester.pumpWidget(harness.app(const CharacterPage()));
    await tester.pump();
    await tester.pump();

    final before = (await harness.settings.get())?.characterId;
    await tester.tap(find.text('咕嘎'));
    await tester.pump();

    expect((await harness.settings.get())?.characterId, before);
    expect(harness.container.read(currentCharacterProvider).id,
        CharacterId.guga);
  });

  testWidgets('C-17 长按角色 → 跳形象页（用回调验证，不播动作）', (tester) async {
    var tapped = 0;
    var longPressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CharacterView(
            spec: CharacterCatalog.resolve('guga', 0),
            height: 150,
            line: '在的',
            onTap: () => tapped++,
            onLongPress: () => longPressed++,
            onBubbleTap: () {},
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.longPress(find.byType(CharacterView));
    await tester.pump();

    expect(longPressed, 1);
    expect(tapped, 0, reason: '长按不触发点击动作、不进对话');
  });
}

/// 极简脚手架：真内存库 + ProviderContainer（可读 provider 断言状态）
class _Harness {
  _Harness() {
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      userSettingsProvider.overrideWith(
          (ref) => UserSettingsRepositoryImpl(db).get()),
    ]);
  }

  final db = fakeDatabase();
  late final ProviderContainer container;

  UserSettingsRepositoryImpl get settings => UserSettingsRepositoryImpl(db);

  void dispose() {
    container.dispose();
    db.close();
  }

  Future<void> seedWeightLoss(double lossJin) async {
    // 起始 70 斤 → 最低 (70 - loss) 斤
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 1, 1), weightKg: 35));
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
        date: DateTime(2025, 2, 1), weightKg: (70 - lossJin) / 2));
  }

  Widget app(Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    );
  }
}
