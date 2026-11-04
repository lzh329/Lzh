import 'package:flutter/material.dart';

/// 首页角色的**手势层**：点击 / 长按 / 拖拽回弹。
///
/// 为什么单独一个组件（而不是塞进 `CharacterView`）：
/// 拖拽需要 `Listener` 原始指针事件（为了 6px 的细阈值）+ 一个回弹用的
/// AnimationController + "拖过就别再触发点击"的抑制逻辑，这三件事跟
/// "Rive 优先/程序化降级"毫无关系，混在一起会把 CharacterView 顶破 300 行。
///
/// 三个关键数字：
/// - **6px** 才算拖拽（Flutter 自带 pan 判定是 18px，对"捏起来晃一晃"太迟钝）
/// - **±40px** 位移上限（再大就会盖住首页的卡片，把布局晃散）
/// - 松手用 `elasticOut` 回弹（带一点 overshoot，像有橡皮筋）
class CharacterGestureArea extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 拖拽开始/结束回调（拖拽期间父级可以停掉随机小动作，避免"手还没松就自己动"）
  final ValueChanged<bool>? onDragStateChanged;

  const CharacterGestureArea({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onDragStateChanged,
  });

  /// 拖拽阈值（逻辑像素）
  static const dragThreshold = 6.0;

  /// 位移上限
  static const maxOffset = 40.0;

  /// 回弹时长
  static const springDuration = Duration(milliseconds: 420);

  @override
  State<CharacterGestureArea> createState() => CharacterGestureAreaState();
}

class CharacterGestureAreaState extends State<CharacterGestureArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;

  /// 当前位移（拖拽中直接跟手；松手后由 _spring 归零）
  Offset _offset = Offset.zero;

  /// 本次按下的起点（用来算 6px 阈值）
  Offset? _downAt;

  /// 本次是否已经进入拖拽（决定抬手算"点击"还是"拖拽结束"）
  bool _dragging = false;

  /// 回弹起点（松手那一刻的位移）
  Offset _springFrom = Offset.zero;

  /// 拖拽位移（测试与父级读）
  Offset get offset => _offset;

  bool get isDragging => _dragging;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: CharacterGestureArea.springDuration,
    )..addListener(_onSpringTick);
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  void _onSpringTick() {
    final t = Curves.elasticOut.transform(_spring.value.clamp(0.0, 1.0));
    setState(() => _offset = _springFrom * (1 - t));
  }

  void _handlePointerDown(PointerDownEvent event) {
    _downAt = event.position;
    _dragging = false;
    _spring.stop();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final down = _downAt;
    if (down == null) return;
    final delta = event.position - down;
    if (!_dragging && delta.distance < CharacterGestureArea.dragThreshold) {
      return; // 还没到阈值：仍可能是"点击"，先不动
    }
    if (!_dragging) {
      _dragging = true;
      widget.onDragStateChanged?.call(true);
    }
    setState(() {
      // 逐轴夹紧：斜着甩也不能超出 ±40（否则会盖住左右两侧的卡片）
      _offset = Offset(
        delta.dx.clamp(-CharacterGestureArea.maxOffset,
            CharacterGestureArea.maxOffset),
        delta.dy.clamp(-CharacterGestureArea.maxOffset,
            CharacterGestureArea.maxOffset),
      );
    });
  }

  void _handlePointerUp() {
    _downAt = null;
    if (!_dragging) return; // 是点击，交给 onTap
    _dragging = false;
    widget.onDragStateChanged?.call(false);
    _springFrom = _offset;
    // 松手回弹：从当前位移弹回 0（elasticOut 自带 overshoot）
    _spring.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _handlePointerUp(),
      onPointerCancel: (_) => _handlePointerUp(),
      child: Transform.translate(
        // 只位移、不改布局：舞台内部一个像素都不动，首页卡片也不会被挤压
        offset: _offset,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _dragging ? null : widget.onTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      ),
    );
  }
}
