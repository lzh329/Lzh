import 'package:flutter/material.dart';

/// 骨架屏占位组件，用于数据加载中的闪烁动画
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark
        ? theme.colorScheme.onSurface.withAlpha(15)
        : theme.colorScheme.onSurface.withAlpha(12);
    final highlight = isDark
        ? theme.colorScheme.onSurface.withAlpha(30)
        : theme.colorScheme.onSurface.withAlpha(25);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: [
                (_controller.value - 0.5).clamp(0.0, 1.0),
                _controller.value.clamp(0.0, 1.0),
                (_controller.value + 0.5).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 列表页骨架屏：标题栏 + 3 行占位
class ShimmerList extends StatelessWidget {
  const ShimmerList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(5, (i) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const ShimmerBox(width: 48, height: 48, borderRadius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(
                      height: 14,
                      width: i == 2 ? 120 : 180,
                    ),
                    const SizedBox(height: 8),
                    const ShimmerBox(height: 12, width: 100),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
