import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_idle_gesture.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_mood.dart';

/// 程序化降级动画 —— **全库唯一的呼吸/摆头实现**。
///
/// 吸收了两份历史实现，不再有第二份：
/// - 分层（有 `_head`/`_body` 拆分图）：`guga_puppet.dart`（已删除）
/// - 单图（没有拆分图）：`guga_stand.dart`（原本全库零引用，正好复用行为）
///
/// 为什么两条分支由**声明**决定（`spec.hasSplit`）而不是按角色名硬编码：
/// 将来给糯糯补出拆分图，只要在注册表里加两行常量就生效，不用改这里。
///
/// 为什么它永不卸载：`CharacterView` 用 `Visibility(maintainState)` 把它藏在
/// Rive 图层下面（决策 4/d）。降级时只翻转可见性 —— 不重建子树 ⇒ 不闪、不跳。
class CharacterProceduralView extends StatefulWidget {
  /// 渲染依据（资产路径只从这里取，绝不拼字符串）
  final CharacterRenderSpec spec;

  /// 立绘高度（逻辑像素）。宽度按 0.82 比例算，与渲染模式无关 ⇒ 切换不 relayout。
  final double height;

  /// 点击脉冲：父级每次"允许播动作的点击"+1；值变化时播一次摆动/弹跳。
  ///
  /// 为什么用计数而不是回调：动画归属这个组件，父级不该持有 controller；
  /// 计数变化在 `didUpdateWidget` 里触发一次性动画，天然防抖（值不变不重播）。
  final int tapTick;

  /// 强制单图（测试/手动验收用）；默认 false = 按 `spec.hasSplit` 走
  final bool forceSingleImage;

  /// 立绘解码失败时回调（C16：隐藏台词气泡，只留图标占位）
  ///
  /// 由 `CharacterView` 接管：它把气泡藏掉，首页其余元素一动不动。
  final void Function()? onAssetMissing;

  /// 活体状态：调制呼吸快慢/幅度与随机小动作强度（阶段 A）
  final CharacterMood mood;

  /// 是否允许随机小动作。点击冷却中 / 拖拽中 / 被 Rive 盖住时传 false。
  ///
  /// 为什么由父级决定而不是自己判断：`_canTap` 在 CharacterView 里，
  /// 这里再存一份冷却状态就成了"两套防抖"，迟早不一致。
  final bool gestureAllowed;

  const CharacterProceduralView({
    super.key,
    required this.spec,
    this.height = 195,
    this.tapTick = 0,
    this.forceSingleImage = false,
    this.onAssetMissing,
    this.mood = CharacterMood.idle,
    this.gestureAllowed = true,
  });

  @override
  State<CharacterProceduralView> createState() =>
      CharacterProceduralViewState();
}

class CharacterProceduralViewState extends State<CharacterProceduralView>
    with TickerProviderStateMixin {
  // 原图高 680：头 353（0.519）、身体 395（0.581，从 0.42 开始）。
  // 这两个比例是分层图的裁切依据，跟角色无关（拆分图按同一规格出）。
  static const _headRatio = 0.519;
  static const _bodyRatio = 0.581;

  late final AnimationController _breath;
  late final AnimationController _tap;
  late final AnimationController _sway;

  /// 随机小动作驱动器（控制器 + 计时器 + 随机参数都在里面）
  late final CharacterIdleGestureDriver _idle;

  /// 播过几次随机小动作（测试用：证明"真的会自己动"）
  int get gesturePlayCount => _idle.playCount;

  bool get _layered => widget.spec.hasSplit && !widget.forceSingleImage;

  @override
  void initState() {
    super.initState();
    // 待机循环：**由动画自己驱动**，不挂任何 Timer（R6 的同一条精神）
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    // 整身待机摇摆：单图角色不能只靠呼吸（幅度太小、几乎看不见），
    // 加一个缓慢的左右晃动（4.6s 一个周期），视觉上"活"很多。
    _sway = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4600),
    )..repeat();
    _idle = CharacterIdleGestureDriver(vsync: this);
    // 呼吸速度跟 mood 走（训练中更快，休息中更慢）
    _breath.duration = CharacterMoodStyle.of(widget.mood).breathCycle;
    // 排第一次随机小动作（6~12s 后；之后自递归重排）
    _idle.schedule(canPlay: _canGesture);
  }

  /// 随机小动作的前置条件：允许 + 界面还在 + 没被 Rive 盖住
  bool _canGesture() => mounted && widget.gestureAllowed;

  @override
  void didUpdateWidget(CharacterProceduralView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 点击脉冲：只有计数变了才播（同一帧连点两次不会把动画重置回第一帧）
    if (widget.tapTick != oldWidget.tapTick) {
      _tap.forward(from: 0);
    }
    // mood 变了：呼吸速度跟着换（不重建控制器，避免动画从头开始）
    if (widget.mood != oldWidget.mood) {
      _breath.duration = CharacterMoodStyle.of(widget.mood).breathCycle;
      if (_breath.isAnimating) _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _idle.dispose(); // 内含 timer.cancel()，不 cancel 会在 unmounted 上 setState
    _breath.dispose();
    _tap.dispose();
    _sway.dispose();
    super.dispose();
  }

  /// 图缺失时的兜底（决策 8 第 3 层）：内置图标 + 不留白框。
  ///
  /// 正常情况下走不到这里（`asset_guard_test` 会拦住缺图），但它是最后一道保险：
  /// 用户看到图标总比看到白框好，而且其余首页元素一动不动。
  Widget _missing(BuildContext context, Object error, StackTrace? stack) {
    debugPrint('角色立绘缺失：$error');
    // errorBuilder 发生在 build 期间，回调要推到帧末（父级会 setState）
    final cb = widget.onAssetMissing;
    if (cb != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) => cb());
    }
    return const Center(
      child: Icon(
        Icons.sentiment_satisfied_alt,
        size: 96,
        color: AppColors.textTertiary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final style = CharacterMoodStyle.of(widget.mood);

    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _tap, _sway, _idle.controller]),
      builder: (context, _) {
        final b = _breath.value; // 0~1（reverse repeat）
        final t = _tap.value; // 0~1
        final s = _sway.value; // 0~1

        // 浮动相位：0（沉）→ 1（浮到最高）→ 0，正弦过渡更顺滑
        final bob = math.sin(b * math.pi);

        // 随机小动作：单峰包络（起→峰→落），四个通道按 kind 只启用一个
        final env = _idle.envelope;
        final gesture = _idle.current;
        final amp = gesture.amplitude * style.gestureScale;
        var extraDy = 0.0;
        var extraDx = 0.0;
        var extraAngle = 0.0;
        var extraSquash = 0.0;
        switch (gesture.kind) {
          case IdleGestureKind.hop: // 轻跳
            extraDy = -env * 12 * amp;
          case IdleGestureKind.tilt: // 左右倾
            extraAngle = env * 0.055 * amp * gesture.direction;
          case IdleGestureKind.squash: // 压扁回弹
            extraSquash = env * 0.05 * amp;
          case IdleGestureKind.shift: // 小幅平移（**上限 10px**，不会跑出可视区）
            extraDx = env * 10 * amp * gesture.direction;
        }

        // 垂直浮动：像"大肥鱼"一样在水里一浮一沉（幅度比旧版呼吸大得多）
        final dy = -bob * 7 - (_layered ? 0 : _bounceLift(t)) + extraDy;

        // 挤压拉伸：上浮时略微拉长、下沉时略微压扁（软乎乎的"活物"感）
        // 幅度走 mood（训练中更明显、休息中几乎看不见）
        final squash = bob * style.breathScale;
        final scaleX =
            1.0 - squash - extraSquash + (_layered ? 0 : _bounceScale(t));
        final scaleY = 1.0 + (squash + extraSquash) * 1.3;

        // 单图角色的整身摇摆（分层角色的头已经会摆，整身再加会过量）
        final swayAngle =
            (_layered ? 0.0 : math.sin(s * math.pi * 2) * 0.02) + extraAngle;

        return Transform.translate(
          offset: Offset(extraDx, dy),
          child: Transform.rotate(
            angle: swayAngle,
            alignment: Alignment.bottomCenter,
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: SizedBox(
                width: h * 0.82,
                height: h,
                child: _layered ? _buildLayered(h, b, t) : _buildSingle(h),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 分层呼吸：身体不动，头绕脖子（底边中心）摆
  ///
  /// 头部角度 = 待机微摆（随呼吸）+ 点击摆动（5 个半周期衰减）
  Widget _buildLayered(double h, double b, double t) {
    final idleAngle = math.sin(b * math.pi * 2) * 0.012;
    final tapAngle = t > 0 && t < 1
        ? math.sin(t * math.pi * 5) * 0.09 * (1 - t)
        : 0.0;
    final headAngle = idleAngle + tapAngle;

    return Stack(
      children: [
        // 身体（底层，底部对齐）
        Align(
          alignment: Alignment.bottomCenter,
          child: Image.asset(
            widget.spec.bodyAsset!,
            height: h * _bodyRatio,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: _missing,
          ),
        ),
        // 头（上层，顶部对齐，绕脖子旋转）
        Align(
          alignment: Alignment.topCenter,
          child: Transform.rotate(
            angle: headAngle,
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              widget.spec.headAsset!,
              height: h * _headRatio,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: _missing,
            ),
          ),
        ),
      ],
    );
  }

  /// 单图呼吸：整图缩放 + 弹跳（糯糯/菲比没有拆分图）
  Widget _buildSingle(double h) {
    final asset = widget.spec.imageAsset;
    if (asset == null) {
      return _missing(context, '未声明立绘路径', null);
    }
    return Image.asset(
      asset,
      height: h,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: _missing,
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