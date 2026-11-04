import 'package:flutter/material.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_mood.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_procedural.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart'
    show CharacterRenderMode;

/// 角色"两层舞台"：程序化图层（常驻）+ Rive 叶子（预检通过后挂上）。
///
/// 为什么单独成文件（而不是塞在 `character_view.dart` 的 build 里）：
/// 这一段是本期最容易写出闪烁的代码，四个硬约束都必须一眼看全 ——
/// 1. 尺寸只由 `height` 决定，与渲染模式无关 ⇒ 切换不 relayout，不跳；
/// 2. 程序化图层 `Visibility(maintainState)` 只隐藏不卸载 ⇒ 不闪、帧连续；
/// 3. 隐藏时 `TickerMode(enabled: false)` 停掉呼吸动画（不 dispose）⇒ CPU 归零；
/// 4. Rive 叶子用固定 key，只在预检通过后挂 ⇒ 同屏 ≤1 controller（R11）。
class CharacterStage extends StatelessWidget {
  const CharacterStage({
    super.key,
    required this.spec,
    required this.height,
    required this.mode,
    required this.tapTick,
    required this.leafReady,
    required this.rive,
    required this.onFirstFrame,
    required this.onDegrade,
    required this.onAssetMissing,
    this.mood = CharacterMood.idle,
    this.gestureAllowed = true,
  });

  final CharacterRenderSpec spec;
  final double height;
  final CharacterRenderMode mode;
  final int tapTick;

  /// 预检通过、叶子已挂上（等首帧）
  final bool leafReady;
  final CharacterRiveController? rive;

  final void Function() onFirstFrame;
  final void Function(RiveFallbackReason reason) onDegrade;
  final void Function() onAssetMissing;

  /// 活体状态与"能否随机小动作"，原样透传给程序化层
  final CharacterMood mood;
  final bool gestureAllowed;

  @override
  Widget build(BuildContext context) {
    // 尺寸只由 height 决定：切换渲染模式不 relayout，不会"跳一下"
    return SizedBox(
      width: height * 0.82,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ① 程序化图层：常驻，降级时它就是唯一可见的那层
          Visibility(
            visible: mode == CharacterRenderMode.procedural,
            maintainState: true,
            maintainSize: true,
            maintainAnimation: true,
            child: TickerMode(
              enabled: mode == CharacterRenderMode.procedural,
              child: CharacterProceduralView(
                spec: spec,
                height: height,
                tapTick: tapTick,
                onAssetMissing: onAssetMissing,
                mood: mood,
                gestureAllowed: gestureAllowed,
              ),
            ),
          ),
          // ② Rive 叶子：预检通过后才挂，固定 key。
          //    条件是 `leafReady` 而不是 `mode == rive`：mode 要等叶子的 onInit
          //    回调首帧后才会变成 rive，用 mode 判断会死锁。
          if (leafReady && rive != null)
            rive!.buildLeaf(onFirstFrame: onFirstFrame, onDegrade: onDegrade),
        ],
      ),
    );
  }
}
