import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 首页「咕嘎分层伪骨骼」—— 头 / 身体分层，代码驱动动画
///
/// 待机：身体呼吸起伏 + 头轻微左右摆
/// 点击：头快速摆动（衰减）+ 整体弹跳 + 震动
class GugaPuppet extends StatefulWidget {
  /// 头部图（含帽子，下沿与身体重叠）
  final String headAsset;

  /// 身体图（含重叠区）
  final String bodyAsset;

  /// 台词池
  final List<String> lines;
  final int lineIndex;

  /// 整体高度
  final double height;

  final VoidCallback? onTap;

  /// 气泡是否作为"AI 教练入口"展示（带聊天图标 + 主题色描边）
  final bool isChatEntry;

  const GugaPuppet({
    super.key,
    required this.headAsset,
    required this.bodyAsset,
    this.lines = const [],
    this.lineIndex = 0,
    this.height = 150,
    this.onTap,
    this.isChatEntry = false,
  });

  @override
  State<GugaPuppet> createState() => _GugaPuppetState();
}

class _GugaPuppetState extends State<GugaPuppet> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _tap;

  // 原图高 680：头 353（0.519）、身体 395（0.581，从 0.42 开始）
  static const _headRatio = 0.519;
  static const _bodyRatio = 0.581;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
  }

  @override
  void dispose() {
    _breath.dispose();
    _tap.dispose();
    super.dispose();
  }

  String get _line {
    if (widget.lines.isEmpty) return '';
    final i = widget.lineIndex.clamp(0, widget.lines.length - 1);
    return widget.lines[i];
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    _tap.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breath, _tap]),
            builder: (context, _) {
              final b = _breath.value;
              final t = _tap.value;

              // 呼吸：轻微放大 + 上浮
              final scale = 1.0 + b * 0.012;
              final dy = -b * 2.5;

              // 头：待机微摆 + 点击摆动（衰减）
              final idleAngle = math.sin(b * math.pi * 2) * 0.012;
              final tapAngle = t > 0 && t < 1
                  ? math.sin(t * math.pi * 5) * 0.09 * (1 - t)
                  : 0.0;
              final headAngle = idleAngle + tapAngle;

              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: h * 0.82,
                    height: h,
                    child: Stack(
                      children: [
                        // 身体（底层，底部对齐）
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Image.asset(
                            widget.bodyAsset,
                            height: h * _bodyRatio,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        // 头（上层，顶部对齐，绕脖子旋转）
                        Align(
                          alignment: Alignment.topCenter,
                          child: Transform.rotate(
                            angle: headAngle,
                            alignment: Alignment.bottomCenter,
                            child: Image.asset(
                              widget.headAsset,
                              height: h * _headRatio,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_line.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: widget.isChatEntry
                  ? AppColors.primary.withAlpha(20)
                  : AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isChatEntry
                    ? AppColors.primary.withAlpha(140)
                    : AppColors.border,
                width: 0.6,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isChatEntry) ...[
                  const Icon(Icons.chat_bubble_outline,
                      size: 12, color: AppColors.primaryText),
                  const SizedBox(width: 4),
                ],
                Text(
                  _line,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: widget.isChatEntry
                        ? AppColors.primaryText
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
