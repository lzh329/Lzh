import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 冷启动是否需要立即锁定（纯函数，便于单测）
///
/// 判据：开了锁 **且** 有非空 PIN。两者缺一都不该锁 ——
/// 只开了开关却没设 PIN 时锁上等于把用户永久挡在门外。
bool shouldLockOnColdStart({
  required bool lockEnabled,
  String? pinCode,
}) =>
    lockEnabled && pinCode != null && pinCode.isNotEmpty;

/// 隐私锁全屏页（替代原来的 AlertDialog）
///
/// 为什么必须是**不透明全屏页**而不是对话框：对话框底下的页面内容在
/// Android 任务切换器缩略图、系统截屏里仍然是可见的 —— 对一个「防止别人
/// 拿你手机时看到体重/饮食记录」的功能来说，那等于没锁。
///
/// ⚠️ 已知局限（本期不做，写在这里防止误以为已解决）：
/// 1. Android 任务切换器里的**快照**要靠 `FLAG_SECURE` 才能真正遮住，
///    需要走平台通道（无现成插件），本期没做 —— 本页只保证"回到前台时
///    内容被遮住"。
/// 2. 没有输错锁定倒计时：单人自用场景下，把自己锁死的风险大于收益。
class LockScreen extends StatefulWidget {
  /// 正确的 4 位 PIN
  final String correctPin;

  /// 校验通过
  final VoidCallback onUnlocked;

  const LockScreen({
    super.key,
    required this.correctPin,
    required this.onUnlocked,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _input = '';
  String? _error;
  int _failCount = 0;

  void _tap(String digit) {
    if (_input.length >= 4) return;
    setState(() {
      _input += digit;
      _error = null;
    });
    if (_input.length == 4) _verify();
  }

  void _backspace() {
    if (_input.isEmpty) return;
    setState(() {
      _input = _input.substring(0, _input.length - 1);
      _error = null;
    });
  }

  void _verify() {
    if (_input == widget.correctPin) {
      widget.onUnlocked();
      return;
    }
    _failCount++;
    setState(() {
      _input = '';
      _error = _failCount >= 3 ? 'PIN 码错误（已错 $_failCount 次）' : 'PIN 码错误';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // 禁止返回键 / 手势绕过锁屏
      canPop: false,
      child: Scaffold(
        // 必须不透明：任何透明都会让底下的页面在截屏里露出来
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 44),
              const SizedBox(height: 14),
              Text('请输入 PIN 码解锁', style: theme.textTheme.titleMedium),
              const SizedBox(height: 18),
              // 四个点位：已输入的填实心
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _input.length
                            ? AppColors.primary
                            : AppColors.surfaceMuted,
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 34,
                child: Center(
                  child: _error == null
                      ? const SizedBox.shrink()
                      : Text(
                          _error!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.danger),
                        ),
                ),
              ),
              const Spacer(),
              _keypad(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('退出应用'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keypad() {
    Widget key(String label, {VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 72,
            height: 56,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(label, style: const TextStyle(fontSize: 20)),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final d in row) key(d, onTap: () => _tap(d))],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 84),
              key('0', onTap: () => _tap('0')),
              Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  width: 72,
                  height: 56,
                  child: TextButton(
                    onPressed: _backspace,
                    child: const Icon(Icons.backspace_outlined, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
