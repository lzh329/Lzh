import 'dart:async';
import 'dart:ui';

/// 单次倒计时控制器，封装 Timer 生命周期与剩余秒数
class CountdownController {
  Timer? _timer;
  int remaining = 0;
  bool isActive = false;

  /// 开始倒计时，每秒 onTick；归零时调用 onComplete 并自动停止
  void start(int totalSeconds, {
    required VoidCallback onComplete,
    VoidCallback? onTick,
  }) {
    cancel();
    remaining = totalSeconds;
    isActive = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (remaining <= 1) {
        cancel();
        onComplete();
      } else {
        remaining--;
        onTick?.call();
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    isActive = false;
    remaining = 0;
  }

  void dispose() => cancel();
}
