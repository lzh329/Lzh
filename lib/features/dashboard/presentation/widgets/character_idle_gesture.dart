import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// 四种随机小动作。
///
/// 为什么是"四种固定动作"而不是连续噪声：桌宠的可爱来自**可辨识的小动作**，
/// 连续抖动只会像信号不好。四种各占一个通道（上下 / 旋转 / 挤压 / 左右），
/// 叠加时也不会互相抵消成"没动"。
enum IdleGestureKind { hop, tilt, squash, shift }

/// 一次小动作的随机参数
class IdleGesture {
  final IdleGestureKind kind;

  /// 方向（±1）：倾斜与平移用，轻跳/压扁不看它
  final double direction;

  /// 幅度倍率 0.7~1.0（不取满值，避免每次都像"到点了"）
  final double amplitude;

  const IdleGesture({
    required this.kind,
    required this.direction,
    required this.amplitude,
  });
}

/// 随机小动作的**驱动器**：一个 AnimationController + 一个可取消的 Timer。
///
/// 为什么不是混在 `CharacterProceduralView` 里：
/// ① 那里已经贴着 300 行纪律；
/// ② "什么时候该动、动多大幅度"是可以单独测的（不需要 pump 界面），
///    而这恰恰是最容易写错的部分（Timer 泄漏、动作叠加、幅度越界）。
///
/// 四个不变量：
/// - Timer **可取消**且 dispose 必调（否则 unmounted 上 setState 崩）；
/// - 动作**不叠加**（上一个还在播就跳过这一轮，等下一个 6~12s）；
/// - 父级说不能动（点击冷却 / 拖拽中 / 被 Rive 盖住）就跳过；
/// - 幅度有上限（平移 ≤10px、跳 ≤12px、倾 ≤0.055rad），不会甩出可视区。
class CharacterIdleGestureDriver {
  CharacterIdleGestureDriver({required TickerProvider vsync})
      : controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 320),
        );

  final AnimationController controller;

  Timer? _timer;
  final math.Random _random = math.Random();

  IdleGesture _current = const IdleGesture(
    kind: IdleGestureKind.hop,
    direction: 1,
    amplitude: 1,
  );

  /// 播过几次（测试用：证明"真的会自己动"）
  int playCount = 0;

  IdleGesture get current => _current;

  /// 单峰包络 0→1→0（起手轻、中间到位、落回），越小越"柔和"
  double get envelope {
    final v = controller.value;
    if (v <= 0 || v >= 1) return 0;
    return math.sin(v * math.pi);
  }

  bool get isPlaying => controller.isAnimating;

  /// 排下一次随机小动作：6~12s 后（自递归，每轮重排）
  void schedule({required bool Function() canPlay}) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: 6 + _random.nextInt(7)), () {
      playNow(canPlay: canPlay);
      schedule(canPlay: canPlay);
    });
  }

  /// 立刻试播一次；返回是否真的播了（被挡掉时 false，便于测试断言）
  bool playNow({required bool Function() canPlay}) {
    if (!canPlay() || isPlaying) return false;
    _current = IdleGesture(
      kind: IdleGestureKind
          .values[_random.nextInt(IdleGestureKind.values.length)],
      direction: _random.nextBool() ? 1 : -1,
      amplitude: 0.7 + _random.nextDouble() * 0.3,
    );
    controller.duration = Duration(milliseconds: 250 + _random.nextInt(200));
    controller.forward(from: 0);
    playCount++;
    return true;
  }

  void dispose() {
    _timer?.cancel(); // 不 cancel 会在 unmounted 上 setState
    _timer = null;
    controller.dispose();
  }
}
