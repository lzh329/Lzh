import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 首页「咕嘎站立区」—— 3D 立绘 + 呼吸浮动 + 点击切换动作 + 台词气泡
///
/// 阶段 1 的程序化微动画：无需骨骼模型，纯代码实现「立体感 + 互动」。
class GugaStand extends StatefulWidget {
  /// 待机立绘资源
  final String asset;

  /// 动作帧（点击时轮换播放，播放完回到待机）
  final List<String> actions;

  /// 台词池（按 lineIndex 取一句）
  final List<String> lines;
  final int lineIndex;

  /// 立绘高度
  final double height;

  final VoidCallback? onTap;

  const GugaStand({
    super.key,
    required this.asset,
    this.actions = const [],
    this.lines = const [],
    this.lineIndex = 0,
    this.height = 150,
    this.onTap,
  });

  @override
  State<GugaStand> createState() => _GugaStandState();
}

class _GugaStandState extends State<GugaStand> with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _bounce;

  /// -1 = 待机；>=0 = 动作帧索引
  int _actionIndex = -1;
  Timer? _actionTimer;

  @override
  void initState() {
    super.initState();
    // 呼吸 / 待机浮动（循环）
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    // 点击弹跳（一次性）
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _actionTimer?.cancel();
    _breath.dispose();
    _bounce.dispose();
    super.dispose();
  }

  /// 当前展示的立绘（动作优先，播放完回待机）
  String get _currentAsset {
    if (_actionIndex >= 0 && _actionIndex < widget.actions.length) {
      return widget.actions[_actionIndex];
    }
    return widget.asset;
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    if (widget.actions.isNotEmpty) {
      setState(() {
        _actionIndex =
            _actionIndex + 1 >= widget.actions.length ? 0 : _actionIndex + 1;
      });
      _actionTimer?.cancel();
      _actionTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _actionIndex = -1);
      });
    }
    _bounce.forward(from: 0);
    widget.onTap?.call();
  }

  String get _line {
    if (widget.lines.isEmpty) return '';
    final i = widget.lineIndex.clamp(0, widget.lines.length - 1);
    return widget.lines[i];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([_breath, _bounce]),
            builder: (context, child) {
              final b = _breath.value; // 0 ~ 1
              final t = _bounce.value; // 0 ~ 1

              // 呼吸：轻微放大 + 上浮
              final scale = 1.0 + b * 0.012 + _bounceScale(t);
              final dy = -b * 3.0 - _bounceLift(t);

              return Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.bottomCenter,
                  child: child,
                ),
              );
            },
            child: Image.asset(
              _currentAsset,
              height: widget.height,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        if (_line.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border, width: 0.6),
            ),
            child: Text(
              _line,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  /// 点击弹跳：先放大再回弹（正弦近似）
  double _bounceScale(double t) {
    if (t <= 0 || t >= 1) return 0;
    return math.sin(t * math.pi) * 0.055 - math.sin(t * math.pi * 2) * 0.02;
  }

  /// 点击时轻微上跳
  double _bounceLift(double t) {
    if (t <= 0 || t >= 1) return 0;
    return math.sin(t * math.pi) * 12;
  }
}
