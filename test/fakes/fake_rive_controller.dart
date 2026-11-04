import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart';

import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';

/// 测试用假 Rive 控制器。
///
/// 为什么需要它：宿主 VM（`flutter test`）里没有 `rive_common` 的原生库，
/// 真实的 `RiveFile.asset` 必然抛错。要验证"点击发一次 trigger / 防抖 /
/// 台词开关 / 升级庆祝"这些**行为契约**，只能把状态机换成一个记录调用的假实现。
///
/// 它同时实现 `CharacterRiveController`，所以假实现与真实现共用同一份接口 ——
/// 接口漂移时两边一起编译失败，不会出现"测试通过但线上是另一套"。
class FakeRiveController implements CharacterRiveController {
  FakeRiveController({
    this.preflightResult = const RiveLoadResult.ok(),
    this.hasTapInput = true,
    this.missingStateMachine = false,
    this.autoFirstFrame = true,
  });

  /// 预检结果（默认成功）
  final RiveLoadResult preflightResult;

  /// 有没有 `tap` 输入（R5：缺输入只是"点不动"，不降级）
  final bool hasTapInput;

  /// 有文件但取不到 `main`（R5 的第二种降级）
  final bool missingStateMachine;

  /// buildLeaf 后是否自动出首帧（false 用来测首帧超时）
  final bool autoFirstFrame;

  int preflightCount = 0;
  int tapCount = 0;
  int celebrateCount = 0;
  int disposeCount = 0;
  int? lastForm;
  bool? lastSpeaking;

  /// 记录"有没有被 dispose 后再被使用"（R11：死掉的 controller 不许再用）
  bool get isDisposed => disposeCount > 0;

  @override
  Future<RiveLoadResult> preflight(String rivPath) async {
    preflightCount++;
    return preflightResult;
  }

  @override
  Widget buildLeaf({
    required void Function() onFirstFrame,
    required void Function(RiveFallbackReason reason) onDegrade,
  }) {
    if (missingStateMachine) {
      return _FakeLeaf(
        key: const ValueKey('rive'),
        onMounted: () => onDegrade(RiveFallbackReason.stateMachineMissing),
      );
    }
    return _FakeLeaf(
      key: const ValueKey('rive'),
      onMounted: autoFirstFrame ? onFirstFrame : null,
    );
  }

  @override
  bool fireTap() {
    if (!hasTapInput) return false;
    tapCount++;
    return true;
  }

  @override
  void setSpeaking(bool value) {
    lastSpeaking = value;
  }

  @override
  void setForm(int form) {
    lastForm = form;
  }

  @override
  void fireCelebrate() {
    celebrateCount++;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}

/// 叶子占位：在帧末回调（模拟真实 `RiveAnimation.onInit` 的时机，
/// 避免在 build 期间对祖先 setState）
class _FakeLeaf extends StatefulWidget {
  const _FakeLeaf({super.key, this.onMounted});

  final void Function()? onMounted;

  @override
  State<_FakeLeaf> createState() => _FakeLeafState();
}

class _FakeLeafState extends State<_FakeLeaf> {
  @override
  void initState() {
    super.initState();
    final cb = widget.onMounted;
    if (cb == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) cb();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
