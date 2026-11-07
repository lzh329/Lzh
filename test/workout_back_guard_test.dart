import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 训练中的系统返回键：第一次只提示，2 秒内再按一次才退出
///
/// 用源码守卫而不是 pump 整个训练页：训练页依赖会话状态机 + 通知通道，
/// 起一座假会话的成本远高于这条不变量本身。真正要锁的是"别直接 pop"。
void main() {
  final src = File(
          'lib/features/workout/presentation/pages/workout_active_page.dart')
      .readAsStringSync();

  test('训练页用 PopScope 拦截系统返回，canPop 为 false', () {
    expect(src.contains('PopScope('), isTrue);
    expect(src.contains('canPop: false'), isTrue,
        reason: 'canPop 为 true 时按一次返回就直接离开训练');
  });

  test('第一次返回只提示「再按一次返回键退出训练」', () {
    expect(src.contains('再按一次返回键退出训练'), isTrue);
    expect(src.contains('_handleSystemBack'), isTrue);
  });

  test('双击窗口存在且第二次才 pop', () {
    expect(src.contains('Duration(seconds: 2)'), isTrue, reason: '双击窗口');
    expect(src.contains('Navigator.of(context).pop();'), isTrue,
        reason: '第二次返回必须真的退出训练');
  });
}
