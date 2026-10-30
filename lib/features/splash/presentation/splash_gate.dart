import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// Flutter 层启动页：显示全屏插画，最短停留一小会儿后淡出到主界面。
///
/// 为什么不用 Android 原生 windowBackground：
/// Android 12+ 的系统 SplashScreen 强制用「应用图标」居中显示（真机实测就是
/// 一个圆形图标 + 纯色底），`windowBackground` 在那套机制下不生效——调多少次
/// xml 都只看到图标。所以原生层只留纯色过渡，真正的插画放在 Flutter 第一帧。
///
/// 时序（踩过的坑）：不能用固定 `Future.delayed(900ms)` 从 initState 直接计时。
/// 系统闪屏退场 + 首帧解码本身可能吃掉几百毫秒，计时器和系统闪屏重叠，
/// 结果用户只看到图标一闪就进主页。这里改成：
/// 1) 先把图 `precacheImage` 进内存（保证首帧就能画出来，不会白一下）
/// 2) 图就绪后**才开始**计 hold 时间
/// 3) hold 结束再淡出
class SplashGate extends StatefulWidget {
  final Widget child;

  /// 图片就绪后的最短展示时长（测试可传 Duration.zero）
  final Duration hold;

  const SplashGate({
    super.key,
    required this.child,
    this.hold = const Duration(milliseconds: 1200),
  });

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  static const _asset = 'assets/splash.jpg';

  @override
  void initState() {
    super.initState();
    _warmUpThenHold();
  }

  Future<void> _warmUpThenHold() async {
    // 先把图解到内存：首帧直接有像素，不会出现"空白一帧"
    try {
      await precacheImage(const AssetImage(_asset), context);
    } catch (_) {
      // 图丢了也要走完流程，回落纯色（见 errorBuilder）
    }
    if (!mounted) return;
    await Future<void>.delayed(widget.hold);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _done
          ? widget.child
          : const _SplashImage(key: ValueKey('splash')),
    );
  }
}

class _SplashImage extends StatelessWidget {
  const _SplashImage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.background,
      child: SizedBox.expand(
        // cover：铺满整屏、不留上下白边（用户要求）。
        // 代价是图比屏幕"宽"，左右各裁掉约 11%——主体（两只企鹅）在中部，
        // 裁的是两侧背景，观感无损。
        child: Image(
          image: AssetImage('assets/splash.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          gaplessPlayback: true,
          errorBuilder: _onImageError,
        ),
      ),
    );
  }

  static Widget _onImageError(
          BuildContext context, Object error, StackTrace? stack) =>
      const ColoredBox(color: AppColors.background);
}
