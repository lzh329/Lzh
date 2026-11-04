import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';

/// R-11 同屏只允许 1 个 state machine controller。
///
/// 为什么这条重要：三个形象卡各起一个 state machine 是最容易踩的写法，
/// 也是"中端机首帧掉到 30fps 以下 + 纹理翻 3 倍"的直接原因。
void main() {
  setUp(RiveControllerBudget.resetForTest);
  tearDown(RiveControllerBudget.resetForTest);

  test('计数器本身：acquire/release 成对时归零', () {
    expect(RiveControllerBudget.liveControllerCount, 0);
    RiveControllerBudget.acquire();
    expect(RiveControllerBudget.liveControllerCount, 1);
    RiveControllerBudget.release();
    expect(RiveControllerBudget.liveControllerCount, 0);
    // 多 release 不会变负（防御性：宁可归零也不要负数掩盖泄漏）
    RiveControllerBudget.release();
    expect(RiveControllerBudget.liveControllerCount, 0);
  });

  testWidgets('进/出角色区 10 次，计数回到 0（不泄漏）', (tester) async {
    final factory = _BudgetedFactory();

    for (var i = 0; i < 10; i++) {
      await tester.pumpWidget(_host(factory.call));
      await tester.pump(); // preflight
      await tester.pump(); // 叶子挂上
      await tester.pump(const Duration(milliseconds: 16)); // 首帧
      expect(RiveControllerBudget.liveControllerCount, lessThanOrEqualTo(1),
          reason: '第 ${i + 1} 次进入时同屏最多 1 个 controller');

      // 离开角色区（整棵树换掉）
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();
      expect(RiveControllerBudget.liveControllerCount, 0,
          reason: '第 ${i + 1} 次离开后必须全部释放');
    }
    expect(factory.created, 10);
  });

  testWidgets('同屏两个角色区会暴露成计数 2（这条红线是可测的）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            CharacterView(
              spec: CharacterCatalog.resolve('guga', 0),
              height: 120,
              controllerFactory: () => _BudgetedController()..attach(),
            ),
            CharacterView(
              spec: CharacterCatalog.resolve('nuonuo', 0),
              height: 120,
              controllerFactory: () => _BudgetedController()..attach(),
            ),
          ],
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 页面上同时有两块角色区 = 2 个 controller。本期唯一合法用法是**只有一块**，
    // 所以这里断言"计数能到 2" —— 说明这条红线是真的被计数着，不是纸面约定。
    expect(RiveControllerBudget.liveControllerCount, 2);
  });

  testWidgets('形象页（若误用 CharacterView）会超预算 —— 所以它必须用静态 Image',
      (tester) async {
    // 形象页只用静态 Image.asset 渲染 3 张卡；这里用 3 个 Image 模拟它的结构，
    // 断言"渲染 3 张图不产生任何 controller"。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            for (final id in ['guga', 'nuonuo', 'phoebe'])
              Image.asset(CharacterCatalog.resolve(id, 0).imageAsset!),
          ],
        ),
      ),
    ));
    await tester.pump();
    expect(RiveControllerBudget.liveControllerCount, 0,
        reason: '3 张卡都是静态 PNG，一个 state machine 都不许起（决策 14）');
  });
}

Widget _host(FakeControllerFactory factory) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: CharacterView(
          spec: CharacterCatalog.resolve('guga', 0),
          height: 120,
          line: '在的',
          controllerFactory: factory,
        ),
      ),
    ),
  );
}

/// 生产计数的假控制器：模拟真实 adapter "一个叶子一个 controller、dispose 时释放"
typedef FakeControllerFactory = CharacterRiveController Function();

class _BudgetedFactory {
  int created = 0;

  CharacterRiveController call() {
    created++;
    return _BudgetedController()..attach();
  }
}

class _BudgetedController implements CharacterRiveController {
  bool _attached = false;

  void attach() {
    if (_attached) return;
    _attached = true;
    RiveControllerBudget.acquire();
  }

  void _release() {
    if (!_attached) return;
    _attached = false;
    RiveControllerBudget.release();
  }

  @override
  Future<RiveLoadResult> preflight(String rivPath) async =>
      const RiveLoadResult.ok();

  @override
  Widget buildLeaf({
    required void Function() onFirstFrame,
    required void Function(RiveFallbackReason reason) onDegrade,
  }) =>
      const SizedBox.expand();

  @override
  bool fireTap() => true;

  @override
  void setSpeaking(bool value) {}

  @override
  void setForm(int form) {}

  @override
  void fireCelebrate() {}

  @override
  void dispose() => _release();
}
