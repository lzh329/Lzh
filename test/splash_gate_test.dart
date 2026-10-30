import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittrack/features/splash/presentation/splash_gate.dart';

/// 启动页：先显示插画，hold 结束后切到主界面，且不拦截后续交互。
void main() {
  testWidgets('hold 期间显示插画，结束后切到 child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashGate(
          hold: Duration(milliseconds: 50),
          child: Text('主界面'),
        ),
      ),
    );

    // 首帧：两层图都在（模糊底 + 完整前景），child 还没出来
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('主界面'), findsNothing);

    // 等 hold 结束 + 切换动画
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();

    expect(find.text('主界面'), findsOneWidget);
  });
}
