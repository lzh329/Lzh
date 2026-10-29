import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/settings/presentation/pages/lock_screen.dart';

void main() {
  group('shouldLockOnColdStart：冷启动是否立刻锁', () {
    test('开关开 + PIN 非空 → 锁', () {
      expect(
        shouldLockOnColdStart(lockEnabled: true, pinCode: '1234'),
        isTrue,
      );
    });

    test('开关开但 PIN 为空 / null → 不锁（否则用户被永久挡在门外）', () {
      expect(shouldLockOnColdStart(lockEnabled: true, pinCode: null), isFalse);
      expect(shouldLockOnColdStart(lockEnabled: true, pinCode: ''), isFalse);
    });

    test('开关关（有 PIN 也不锁）', () {
      expect(
        shouldLockOnColdStart(lockEnabled: false, pinCode: '1234'),
        isFalse,
      );
    });

    test('都没设置 → 不锁（老库 / 首启）', () {
      expect(shouldLockOnColdStart(lockEnabled: false, pinCode: null), isFalse);
    });
  });

  group('LockScreen', () {
    Future<void> pump(
      WidgetTester tester, {
      required String pin,
      required VoidCallback onUnlocked,
    }) {
      return tester.pumpWidget(MaterialApp(
        home: LockScreen(correctPin: pin, onUnlocked: onUnlocked),
      ));
    }

    Future<void> tapDigits(WidgetTester tester, String digits) async {
      for (final d in digits.split('')) {
        await tester.tap(find.widgetWithText(OutlinedButton, d));
        await tester.pump();
      }
    }

    testWidgets('输对 PIN → 触发解锁回调', (tester) async {
      var unlocked = false;
      await pump(tester, pin: '1234', onUnlocked: () => unlocked = true);

      await tapDigits(tester, '1234');
      expect(unlocked, isTrue);
    });

    testWidgets('忘记 PIN：二次确认后清锁（而不是把人永久锁在门外）', (tester) async {
      var unlocked = false;
      var forgotCalled = false;
      await tester.pumpWidget(MaterialApp(
        home: LockScreen(
          correctPin: '1234',
          onUnlocked: () => unlocked = true,
          onForgotPin: () async => forgotCalled = true,
        ),
      ));

      await tester.tap(find.text('忘记 PIN 码？'));
      await tester.pumpAndSettle();
      // 确认框必须说清"数据不会丢"，这是用户此刻最怕的事
      expect(find.textContaining('数据不会被删除'), findsOneWidget);

      await tester.tap(find.text('清除锁屏'));
      await tester.pumpAndSettle();

      expect(forgotCalled, isTrue);
      expect(unlocked, isFalse, reason: '清锁走的是独立回调，不该冒充"输对了"');
    });

    testWidgets('输错 PIN → 显示错误且不解锁', (tester) async {
      var unlocked = false;
      await pump(tester, pin: '1234', onUnlocked: () => unlocked = true);

      await tapDigits(tester, '9999');
      expect(unlocked, isFalse);
      expect(find.text('PIN 码错误'), findsOneWidget);
    });

    testWidgets('连错 3 次 → 提示里带次数（但不做锁定倒计时）', (tester) async {
      var unlocked = false;
      await pump(tester, pin: '1234', onUnlocked: () => unlocked = true);

      for (var i = 0; i < 3; i++) {
        await tapDigits(tester, '0000');
      }
      expect(unlocked, isFalse);
      expect(find.textContaining('已错 3 次'), findsOneWidget);
    });

    testWidgets('输错后回退键可用，重新输入正确仍能解锁', (tester) async {
      var unlocked = false;
      await pump(tester, pin: '1234', onUnlocked: () => unlocked = true);

      await tapDigits(tester, '1299');
      // 回退 4 次清空
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byIcon(Icons.backspace_outlined));
        await tester.pump();
      }
      await tapDigits(tester, '1234');
      expect(unlocked, isTrue);
    });
  });
}
