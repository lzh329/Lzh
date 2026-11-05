import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';

import 'fakes/fake_rive_controller.dart';

/// `CharacterView` 的行为契约 —— **同一组断言跑两遍**（Rive 假实现 / 程序化）。
///
/// 这是 R10 的落地形式：两条渲染路径必须"用户感觉一样"。
/// 如果哪天有人只改了 Rive 分支的交互，这个测试会在程序化那一轮红。
void main() {
  late CharacterRenderSpec spec;
  late String? line;
  late int tapCount;
  late int bubbleCount;
  late int longPressCount;
  late List<FakeRiveController> controllers;
  late CharacterRenderMode? reportedMode;
  late RiveFallbackReason? reportedReason;

  setUp(() {
    spec = CharacterCatalog.resolve('guga', 0); // 咕嘎 1 档
    line = '点我聊聊，我在听';
    tapCount = 0;
    bubbleCount = 0;
    longPressCount = 0;
    controllers = [];
    reportedMode = null;
    reportedReason = null;
  });

  Widget harness({required bool procedural}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: CharacterView(
            spec: spec,
            height: 195,
            line: line,
            isChatEntry: true,
            forceProcedural: procedural,
            controllerFactory: procedural
                ? null
                : () {
                    final fake = FakeRiveController();
                    controllers.add(fake);
                    return fake;
                  },
            onTap: () {
              tapCount++;
              // 父级只换台词，不跳页
              line = '换了一句：$tapCount';
            },
            onBubbleTap: () => bubbleCount++,
            onLongPress: () => longPressCount++,
            onModeResolved: (m, r) {
              reportedMode = m;
              reportedReason = r;
            },
          ),
        ),
      ),
    );
  }

  /// 让 view 完成"预检 → 挂叶子 → 首帧 → 模式确定"
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(); // flush preflight future
    await tester.pump(); // 叶子 build
    await tester.pump(); // 首帧 post-frame → setState
    await tester.pump(const Duration(milliseconds: 16));
  }

  for (final procedural in [true, false]) {
    final label = procedural ? '程序化降级路径' : 'Rive 路径';

    group('$label · R-14 点击语义三分离', () {
      testWidgets('点角色本体：播动作 + 换台词，不跳页', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        await tester.tap(find.byType(CharacterView));
        await tester.pump();

        expect(tapCount, 1, reason: '父级收到 onTap（它负责换台词）');
        expect(line, '换了一句：1');
        expect(bubbleCount, 0, reason: '点角色不进对话');
        expect(longPressCount, 0);
        // 模式回抛给父级（debug 页脚小字用）：程序化 / Rive 各归各位
        expect(reportedMode,
            procedural ? CharacterRenderMode.procedural : CharacterRenderMode.rive);
        expect(reportedReason, RiveFallbackReason.none);

        if (!procedural) {
          expect(controllers.single.tapCount, 1, reason: 'Rive 侧 fire 一次 tap trigger');
        }
      });

      testWidgets('点气泡：进对话，不播动作', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        await tester.tap(find.text(line!));
        await tester.pump();

        expect(bubbleCount, 1);
        expect(tapCount, 0, reason: '点气泡不触发角色动作');
        if (!procedural) {
          expect(controllers.single.tapCount, 0);
        }
      });

      testWidgets('长按角色：进形象页，不播动作、不进对话', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        await tester.longPress(find.byType(CharacterView));
        await tester.pump();

        expect(longPressCount, 1);
        expect(tapCount, 0, reason: '长按不触发点击动作');
        expect(bubbleCount, 0, reason: '长按不进对话');
        if (!procedural) {
          expect(controllers.single.tapCount, 0);
        }
      });
    });

    group('$label · R-15 防抖只换台词', () {
      testWidgets('800ms 内点两次：动作只播一次，台词换两句', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        await tester.tap(find.byType(CharacterView));
        await tester.pump(const Duration(milliseconds: 800));
        await tester.tap(find.byType(CharacterView));
        await tester.pump(const Duration(milliseconds: 16));

        expect(tapCount, 2, reason: '台词永远换');
        if (!procedural) {
          expect(controllers.single.tapCount, 1,
              reason: '冷却期内再点不重启动画，否则动画永远停在第一帧');
        }
      });

      testWidgets('1.5s 之后恢复可点', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        final state = tester.state<CharacterViewState>(find.byType(CharacterView));
        expect(state.canTap, isTrue);

        await tester.tap(find.byType(CharacterView));
        await tester.pump();
        expect(state.canTap, isFalse, reason: '冷却期内不可播新动作');

        await tester.pump(CharacterView.tapCooldown);
        expect(state.canTap, isTrue);
      });
    });

    group('$label · R-16 speaking 随气泡开关', () {
      testWidgets('气泡出现 → true；消失 → false', (tester) async {
        await tester.pumpWidget(harness(procedural: procedural));
        await settle(tester);

        if (!procedural) {
          expect(controllers.single.lastSpeaking, isTrue,
              reason: '首帧时气泡正显示，speaking 必须是 true');
        }

        line = null; // 气泡消失
        await tester.pumpWidget(harness(procedural: procedural));
        await tester.pump();

        if (!procedural) {
          expect(controllers.single.lastSpeaking, isFalse);
        }
        expect(find.textContaining('换了一句'), findsNothing);
      });
    });

    group('$label · R-9 分层 / 单图由声明决定', () {
      testWidgets('咕嘎（有拆分图）渲染 2 个 Image；糯糯（单图）渲染 1 个',
          (tester) async {
        spec = CharacterCatalog.resolve('guga', 0);
        await tester.pumpWidget(harness(procedural: true));
        await settle(tester);
        expect(find.byType(Image), findsNWidgets(2),
            reason: '分层降级：头 + 身体两张图');

        spec = CharacterCatalog.resolve('nuonuo', 0);
        await tester.pumpWidget(harness(procedural: true));
        await settle(tester);
        expect(find.byType(Image), findsOneWidget,
            reason: '单图降级：糯糯没有拆分图');
      });
    });
  }

  group('R-17 升级时 celebrate 只发一次，程序化不发', () {
    testWidgets('form 1 → 2：新文件首帧后 celebrate 一次', (tester) async {
      spec = CharacterCatalog.resolve('guga', 0); // form 1
      await tester.pumpWidget(harness(procedural: false));
      await settle(tester);
      expect(controllers, hasLength(1));
      expect(controllers.first.celebrateCount, 0, reason: '进入页面不算升级');
      expect(controllers.first.lastForm, 1);

      // 录了体重 → form 2（.riv 换成 guga_2.riv，会重建 controller）
      spec = CharacterCatalog.resolve('guga', 7);
      await tester.pumpWidget(harness(procedural: false));
      await settle(tester);

      expect(controllers, hasLength(2), reason: '换文件必须换 controller（R11）');
      expect(controllers.first.isDisposed, isTrue, reason: '旧 controller 必须被 dispose');
      expect(controllers.last.lastForm, 2);
      expect(controllers.last.celebrateCount, 1, reason: '形态变大只发一次 celebrate');

      // 同样的 form 再重建一次：不再庆祝
      await tester.pumpWidget(harness(procedural: false));
      await settle(tester);
      expect(controllers.last.celebrateCount, 1,
          reason: 'form 没变就不该再发 celebrate');
    });

    testWidgets('程序化降级路径不播庆祝（R17 后半句）', (tester) async {
      spec = CharacterCatalog.resolve('guga', 0);
      await tester.pumpWidget(harness(procedural: true));
      await settle(tester);

      spec = CharacterCatalog.resolve('guga', 7);
      await tester.pumpWidget(harness(procedural: true));
      await settle(tester);

      // forceProcedural 下根本没有 controller，celebrate 不可能被发出
      expect(controllers, isEmpty);
      expect(find.byType(Image), findsNWidgets(2),
          reason: '降级路径只换图 + 一句台词，不做庆祝动画');
    });
  });

  group('C6 / R11 换角色丢弃旧 controller', () {
    testWidgets('糯糯 → 菲比：旧 controller dispose，动作不跨角色续播', (tester) async {
      spec = CharacterCatalog.resolve('nuonuo', 0);
      await tester.pumpWidget(harness(procedural: false));
      await settle(tester);
      final first = controllers.single;

      // 在糯糯身上播一次动作
      await tester.tap(find.byType(CharacterView));
      await tester.pump();
      expect(first.tapCount, 1);

      spec = CharacterCatalog.resolve('phoebe', 0);
      await tester.pumpWidget(harness(procedural: false));
      await settle(tester);

      expect(first.isDisposed, isTrue, reason: '旧 controller 必须就地死掉（R11）');
      expect(controllers, hasLength(2));
      final second = controllers.last;
      expect(second.isDisposed, isFalse);
      expect(second.tapCount, 0, reason: '不跨角色续播上一只角色的动作');
      expect(second.lastForm, 1, reason: '新角色从自己的 form 开始（菲比恒 1）');
    });
  });
}
