import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// Flutter 层启动页：显示全屏插画，最短停留一小会儿后淡出到主界面。
///
/// 为什么不用 Android 原生 windowBackground：
/// Android 12+ 的系统 SplashScreen 强制用「应用图标」居中显示（用户实测就是
/// 一个圆形图标 + 纯色底），`windowBackground` 在那套机制下不生效——调多少次
/// xml 都只看到图标。所以原生层只留纯色过渡，真正的插画放在 Flutter 第一帧。
///
/// 时长取舍：900ms 是「看得清插画」与「别让人等」的折中；不跟随数据加载，
/// 因为数据有自己的 loading 态，硬等会让冷启动看起来更慢。
class SplashGate extends StatefulWidget {
  final Widget child;

  /// 最短展示时长（测试可传 Duration.zero）
  final Duration hold;

  const SplashGate({
    super.key,
    required this.child,
    this.hold = const Duration(milliseconds: 900),
  });

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.hold, () {
      if (mounted) setState(() => _done = true);
    });
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
        child: Image(
          image: AssetImage('assets/splash.jpg'),
          fit: BoxFit.cover,
          alignment: Alignment.center,
          // 图丢了也不能红屏：回落纯色（和原生 splash 同色，视觉上无缝）
          errorBuilder: _onImageError,
        ),
      ),
    );
  }

  static Widget _onImageError(
          BuildContext context, Object error, StackTrace? stack) =>
      const ColoredBox(color: AppColors.background);
}
