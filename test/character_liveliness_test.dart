import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_gesture_area.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_mood.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_procedural.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';

/// 首页角色「活体运行时」阶段 A：
/// ① 随机小动作（6~12s 一次，四选一，不叠加）
/// ② 拖拽回弹（±40px，松手弹回原点，不影响点击/长按）
/// ③ 状态感知（idle / training / resting 真的改变动效参数）
void main() {
  final spec = CharacterCatalog.resolve('guga', 0);

  group('③ mood：参数真的不同（不是同一个值换个名字）', () {
    test('三种 mood 的呼吸周期/幅度/动作强度两两不同', () {
      final idle = CharacterMoodStyle.of(CharacterMood.idle);
      final training = CharacterMoodStyle.of(CharacterMood.training);
      final resting = CharacterMoodStyle.of(CharacterMood.resting);

      expect(training.breathCycle, lessThan(idle.breathCycle),
          reason: '训练中呼吸更快');
      expect(resting.breathCycle, greaterThan(idle.breathCycle),
          reason: '休息中更慢');
      expect(training.breathScale, greaterThan(idle.breathScale),
          reason: '训练中幅度更大');
      expect(resting.breathScale, lessThan(idle.breathScale),
          reason: '休息中更轻');
      expect(training.gestureScale, greaterThan(resting.gestureScale),
          reason: '训练中的随机小动作更明显');
      // 三个值不能有任意两个相等（否则"换 mood 没变化"也会通过上面的比较）
      expect({idle.breathCycle, training.breathCycle, resting.breathCycle},
          hasLength(3));
    });

    testWidgets('三种 mood 都能渲染且不崩', (tester) async {
      for (final mood in CharacterMood.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: CharacterProceduralView(
                spec: spec,
                height: 150,
                forceSingleImage: true,
                mood: mood,
              ),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 32));
        expect(tester.takeException(), isNull, reason: 'mood=$mood 不该崩');
        expect(find.byType(CharacterProceduralView), findsOneWidget);
      }
    });
  });

  group('① 随机小动作', () {
    testWidgets('13 秒内至少自己动一次（6~12s 一轮）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CharacterProceduralView(
              spec: spec,
              height: 150,
              forceSingleImage: true,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 32));

      final state = tester.state<CharacterProceduralViewState>(
          find.byType(CharacterProceduralView));
      expect(state.gesturePlayCount, 0, reason: '刚进来还没到 6s');

      // 13s：跨过任何一个 6~12s 的定时点
      await tester.pump(const Duration(seconds: 13));
      expect(state.gesturePlayCount, greaterThanOrEqualTo(1),
          reason: '随机小动作必须真的会播（不是只有 Timer 空转）');
      expect(tester.takeException(), isNull);
    });

    testWidgets('gestureAllowed=false 时不播（点击冷却/拖拽中/被 Rive 盖住）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CharacterProceduralView(
              spec: spec,
              height: 150,
              forceSingleImage: true,
              gestureAllowed: false,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 13));

      final state = tester.state<CharacterProceduralViewState>(
          find.byType(CharacterProceduralView));
      expect(state.gesturePlayCount, 0,
          reason: '被禁时一次都不许播（否则会和点击动作叠在一起）');
    });

    testWidgets('dispose 后不再有 Timer 存活（不 setState on unmounted）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: CharacterProceduralView(
              spec: spec,
              height: 150,
              forceSingleImage: true,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 2));
      // 换掉整棵树 → dispose → 定时器必须被 cancel
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump(const Duration(seconds: 13));
      expect(tester.takeException(), isNull,
          reason: '没 cancel 定时器会在 unmounted 上 setState 崩掉');
    });
  });

  group('② 拖拽回弹', () {
    Widget host({VoidCallback? onTap}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: CharacterView(
                spec: spec,
                height: 150,
                line: null,
                forceProcedural: true,
                onTap: onTap,
              ),
            ),
          ),
        );

    testWidgets('拖 80px：位移被夹在 ±40 内（不会盖住首页卡片）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CharacterView)));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();

      final area = tester.state<CharacterGestureAreaState>(
          find.byType(CharacterGestureArea));
      expect(area.offset.dx, CharacterGestureArea.maxOffset,
          reason: '超过上限必须夹住，否则角色会甩到隔壁卡片上');
      expect(area.offset.dx.abs(),
          lessThanOrEqualTo(CharacterGestureArea.maxOffset));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('松手回弹到原点（offset 归零）', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CharacterView)));
      await gesture.moveBy(const Offset(30, 10));
      await tester.pump();
      final area = tester.state<CharacterGestureAreaState>(
          find.byType(CharacterGestureArea));
      expect(area.offset, const Offset(30, 10));

      await gesture.up();
      await tester.pump(); // 起弹
      await tester.pump(CharacterGestureArea.springDuration);
      await tester.pump(const Duration(milliseconds: 32));

      expect(area.offset.dx.abs(), lessThan(0.5),
          reason: '弹回原点（允许一点点弹性余量）');
      expect(area.offset.dy.abs(), lessThan(0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('拖拽后的抬手不算点击（onTap 不触发）', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(onTap: () => taps++));
      await tester.pump();

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(CharacterView)));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));

      expect(taps, 0, reason: '拖过就不是点击了（阈值 6px）');
    });

    testWidgets('轻点（不动）仍然是点击', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(onTap: () => taps++));
      await tester.pump();

      await tester.tap(find.byType(CharacterView));
      await tester.pump();

      expect(taps, 1, reason: '拖拽阈值不能把点击吃掉');
    });
  });
}
