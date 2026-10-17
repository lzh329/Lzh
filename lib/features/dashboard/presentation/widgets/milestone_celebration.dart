import 'package:flutter/material.dart';

/// 里程碑庆祝弹窗 —— 记录体重累计减重跨过 5 的倍数时触发
Future<void> showMilestoneCelebration(
  BuildContext context,
  int milestoneJin,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭庆祝',
    barrierColor: Colors.black.withAlpha(232),
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (ctx, _, __) => _MilestoneView(milestoneJin: milestoneJin),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MilestoneView extends StatelessWidget {
  final int milestoneJin;

  const _MilestoneView({required this.milestoneJin});

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 光环 + 大数字 ──
            SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 三层扩散光晕
                  const _Glow(size: 236, alpha: 20),
                  const _Glow(size: 188, alpha: 34),
                  const _Glow(size: 144, alpha: 52),
                  Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _green.withAlpha(28),
                      border: Border.all(
                        color: _green.withAlpha(160),
                        width: 1.5,
                      ),
                    ),
                  ),
                  // 数字滚入
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: milestoneJin.toDouble()),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '-${v.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '斤',
                          style: TextStyle(
                            fontSize: 14,
                            color: _green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '减脂里程碑达成',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '累计减重 $milestoneJin 斤',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '每一斤，都是你亲自拿下的',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white54,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.black87,
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '继续加油',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final double size;
  final int alpha;

  const _Glow({required this.size, required this.alpha});

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _green.withAlpha(alpha),
            _green.withAlpha(0),
          ],
        ),
      ),
    );
  }
}
