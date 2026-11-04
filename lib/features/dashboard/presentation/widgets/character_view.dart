import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_bubble.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_gesture_area.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_mood.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_stage.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';

enum CharacterRenderMode { rive, procedural }

/// 首页角色区：Rive 优先、程序化降级（R10）。两层舞台在 `character_stage.dart`，
/// 手势/拖拽在 `character_gesture_area.dart`；这里只管防抖、speaking、模式与降级。
class CharacterView extends StatefulWidget {
  const CharacterView({
    super.key,
    required this.spec,
    this.height = 195,
    this.line,
    this.isChatEntry = true,
    this.onTap,
    this.onBubbleTap,
    this.onLongPress,
    this.forceProcedural = false,
    this.onModeResolved,
    this.controllerFactory,
    this.showBubble = true,
    this.mood = CharacterMood.idle,
  });

  /// 渲染依据（唯一来源，见 `CharacterCatalog.resolve`）
  final CharacterRenderSpec spec;

  /// 立绘高度（逻辑像素）。首屏 195。
  final double height;

  /// 当前台词；null / 空串 → 不画气泡
  final String? line;

  /// 气泡是否作为"AI 教练入口"（主题色描边 + 聊天图标）
  final bool isChatEntry;

  /// 点角色本体：父级决定去哪（首页=进教练，并自动播一次动作）
  final VoidCallback? onTap;

  /// 点气泡：进 `/ai/coach`
  final VoidCallback? onBubbleTap;

  /// 长按：进「我的形象」（不播动作、不进对话，C17）
  final VoidCallback? onLongPress;

  /// 测试/手动验收用：强制走程序化（默认 false）
  final bool forceProcedural;

  /// 回抛"最终模式 + 降级原因"（debug 用）
  final void Function(CharacterRenderMode mode, RiveFallbackReason reason)?
      onModeResolved;

  /// 注入自定义 rive 控制器（测试用）；默认 new 真实 adapter
  final CharacterRiveController Function()? controllerFactory;

  /// 是否显示气泡（素材全缺失时父级传 false，C16）
  final bool showBubble;

  /// 活体状态（阶段 A）：驱动呼吸节奏与随机小动作强度
  final CharacterMood mood;

  @override
  State<CharacterView> createState() => CharacterViewState();

  /// 首帧超时：超过就降级，本次会话不再重试（见 6.2）
  static const firstFrameTimeout = Duration(milliseconds: 500);

  /// 动作恢复窗口：一次性动画期间再点不重启动画（R7/R15）
  static const tapCooldown = Duration(milliseconds: 1500);
}

class CharacterViewState extends State<CharacterView> {
  CharacterRiveController? _rive;
  RiveFallbackReason _reason = RiveFallbackReason.none;
  CharacterRenderMode _mode = CharacterRenderMode.procedural;

  /// 预检通过、叶子已挂上（等首帧）
  bool _leafReady = false;

  bool _canTap = true;
  Timer? _cooldownTimer;
  Timer? _firstFrameTimer;

  /// 点击脉冲：程序化图层靠它播一次摆动/弹跳
  int _tapTick = 0;

  int _lastForm = 1;

  /// 立绘解码失败（C16）：藏气泡、只留图标
  bool _assetFailed = false;

  /// 拖拽中：停掉随机小动作（手还没松它自己又蹦一下很怪）
  bool _dragging = false;

  int _actionCount = 0; // 播过几次动作（点击 + 自动播放），测试与 debug 用
  bool _pendingCelebrate = false; // 形态变大的庆祝等新 `.riv` 首帧后再发

  CharacterRenderMode get mode => // 当前实际渲染模式（debug/测试读）
      widget.forceProcedural ? CharacterRenderMode.procedural : _mode;

  RiveFallbackReason get fallbackReason => _reason;
  bool get canTap => _canTap;
  int get actionCount => _actionCount;

  @override
  void initState() {
    super.initState();
    _lastForm = widget.spec.form;
    _resolveMode();
  }

  @override
  void didUpdateWidget(CharacterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换角色/形态：`.riv` 换文件，旧 controller 必须先死（C6/R11）
    if (oldWidget.spec.rivPath != widget.spec.rivPath ||
        oldWidget.forceProcedural != widget.forceProcedural) {
      final increased = widget.spec.form > oldWidget.spec.form;
      _teardownRive();
      _reason = RiveFallbackReason.none;
      _mode = CharacterRenderMode.procedural;
      _leafReady = false;
      _lastForm = widget.spec.form;
      _pendingCelebrate = increased;
      _assetFailed = false;
      _resolveMode();
    } else if (widget.spec.form != _lastForm) {
      _onFormChanged(oldWidget.spec.form, widget.spec.form);
    }

    // 台词出现/消失 → speaking（R16）
    if (oldWidget.line != widget.line) {
      _syncSpeaking();
    }
  }

  @override
  void dispose() {
    _firstFrameTimer?.cancel(); // 两个计时器都要撤，否则 setState on unmounted
    _cooldownTimer?.cancel();
    _teardownRive();
    super.dispose();
  }

  Future<void> _resolveMode() async {
    if (widget.forceProcedural) {
      widget.onModeResolved?.call(CharacterRenderMode.procedural, RiveFallbackReason.none);
      return;
    }

    final controller = widget.controllerFactory?.call() ?? RiveCharacterAdapter();
    _rive = controller;

    // 首帧计时器在预检**之前**启动：第一个像素来自程序化层（不闪不重试）
    _firstFrameTimer?.cancel();
    _firstFrameTimer = Timer(CharacterView.firstFrameTimeout, () {
      if (!mounted || _mode == CharacterRenderMode.rive) return;
      _degrade(RiveFallbackReason.firstFrameTimeout);
    });

    final result = await controller.preflight(widget.spec.rivPath);
    if (!mounted) return;

    if (!result.ok) {
      _degrade(result.reason);
      return;
    }

    // 叶子挂上，等 onInit 里的 onFirstFrame
    setState(() => _leafReady = true);
  }

  void _onFirstFrame() { // 首帧到手。必须推到帧末：`onInit` 在构建期，直接 setState 会报错
    if (!mounted) return;
    _firstFrameTimer?.cancel();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _mode = CharacterRenderMode.rive;
        _reason = RiveFallbackReason.none;
      });
      // 首帧 + 形态变化后都要发 form（Number 1/2/3）
      _rive?.setForm(widget.spec.form);
      // 形态变大：新文件首帧后发 celebrate 一次（R17）
      if (_pendingCelebrate) {
        _pendingCelebrate = false;
        _rive?.fireCelebrate();
      }
      _syncSpeaking();
      widget.onModeResolved?.call(CharacterRenderMode.rive, RiveFallbackReason.none);
    });
  }

  /// 降级：静默（只 debugPrint），程序化图层从未卸载 ⇒ 不闪
  void _degrade(RiveFallbackReason reason) {
    if (!mounted) return;
    _firstFrameTimer?.cancel();
    _teardownRive();
    setState(() {
      _mode = CharacterRenderMode.procedural;
      _reason = reason;
      _leafReady = false;
    });
    widget.onModeResolved?.call(CharacterRenderMode.procedural, reason);
  }

  void _teardownRive() {
    _rive?.dispose();
    _rive = null;
    _leafReady = false;
  }

  /// 形态变化（同一 `.riv` 内）：只升不降（C7），升了才发 form + celebrate
  void _onFormChanged(int oldForm, int newForm) {
    _lastForm = newForm;
    if (newForm > oldForm) {
      _rive?.setForm(newForm);
      _rive?.fireCelebrate();
    }
  }

  void _handleAssetMissing() { // 立绘也加载不出来 → 藏气泡，页面其余不动（C16）
    if (!mounted || _assetFailed) return;
    setState(() => _assetFailed = true);
  }

  void _syncSpeaking() {
    final visible =
        (widget.line ?? '').isNotEmpty && widget.showBubble && !_assetFailed;
    _rive?.setSpeaking(visible);
  }

  /// 手势（R14）：点角色=父级动作（进教练）；点气泡=进对话；长按=形象页
  void _handleCharacterTap() {
    HapticFeedback.lightImpact();
    _startAction();
    widget.onTap?.call();
  }

  /// 播一次动作（点击与"进入首页自动播"共用这一条路径，防抖也共用）
  void _startAction() {
    if (!_canTap) return; // 冷却期内不重启动画，否则动画永远停在第一帧（R15）
    _canTap = false;
    _actionCount++;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(CharacterView.tapCooldown, () {
      if (mounted) setState(() => _canTap = true);
    });
    if (mode == CharacterRenderMode.rive) {
      _rive?.fireTap();
    } else {
      setState(() => _tapTick++);
    }
  }

  /// 外部触发一次动作（首页"进入自动播一次"用）。
  /// 走 `_startAction`：自动播与手点必须同一段动画，否则两侧会只改一边。
  void playActionOnce() => _startAction();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CharacterGestureArea(
          onTap: _handleCharacterTap,
          onLongPress: widget.onLongPress,
          onDragStateChanged: (dragging) =>
              setState(() => _dragging = dragging),
          child: CharacterStage(
            spec: widget.spec,
            height: widget.height,
            mode: mode,
            tapTick: _tapTick,
            leafReady: _leafReady,
            rive: _rive,
            onFirstFrame: _onFirstFrame,
            onDegrade: _degrade,
            onAssetMissing: _handleAssetMissing,
            mood: widget.mood,
            // 冷却中 / 拖拽中 / 被 Rive 盖住时不放随机小动作
            gestureAllowed: mode == CharacterRenderMode.procedural &&
                _canTap &&
                !_dragging &&
                !_assetFailed,
          ),
        ),
        if (widget.showBubble &&
            !_assetFailed &&
            (widget.line ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          // 气泡是独立热区（点它进对话，不播动作，R14）
          GestureDetector(
            onTap: widget.onBubbleTap,
            behavior: HitTestBehavior.opaque,
            child: CharacterBubble(
              line: widget.line!,
              isChatEntry: widget.isChatEntry,
            ),
          ),
        ],
      ],
    );
  }
}
