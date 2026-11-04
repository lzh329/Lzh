import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart'
    show Alignment, BoxFit, SizedBox, ValueKey, Widget;
import 'package:rive/rive.dart';

/// 降级原因（只进 `debugPrint` 与 debug 构建下的页脚小字，**不弹窗不写库**，C15/R8）
enum RiveFallbackReason {
  /// Rive 正常工作
  none,

  /// `rootBundle.load` / `RiveFile.asset` 抛错 → 文件不在
  fileMissing,

  /// 解析异常（数据损坏 / 运行时缺原生库 / 其它未知异常）
  parseFailed,

  /// 数据版本高于运行时支持的版本
  versionUnsupported,

  /// 首帧 500ms 未出图（或预检超过 2s）
  firstFrameTimeout,

  /// 找不到名为 `main` 的 state machine
  stateMachineMissing,
}

extension RiveFallbackReasonLabel on RiveFallbackReason {
  /// debug 页脚用的一行说明（用户看不到，线上也不出现）
  String get label => switch (this) {
        RiveFallbackReason.none => '正常',
        RiveFallbackReason.fileMissing => '文件缺失',
        RiveFallbackReason.parseFailed => '解析失败',
        RiveFallbackReason.versionUnsupported => '版本不兼容',
        RiveFallbackReason.firstFrameTimeout => '首帧超时',
        RiveFallbackReason.stateMachineMissing => '缺少 main 状态机',
      };
}

/// 预检结果
class RiveLoadResult {
  final bool ok;
  final RiveFallbackReason reason;

  const RiveLoadResult.ok()
      : ok = true,
        reason = RiveFallbackReason.none;

  const RiveLoadResult.failed(this.reason) : ok = false;
}

/// 同屏 controller 计数器（R11 的可测形式）。
///
/// 线上语义只有两个值：0（没挂）或 1（首页角色区挂着）。
/// 形象页 3 张卡**一律静态 PNG**，所以进出形象页这个计数不应该是 1。
class RiveControllerBudget {
  RiveControllerBudget._();

  static int _live = 0;

  static int get liveControllerCount => _live;

  static void acquire() => _live++;

  static void release() {
    if (_live > 0) _live--;
  }

  @visibleForTesting
  static void resetForTest() => _live = 0;
}

/// 状态机驱动的最小接口 —— `CharacterView` 只依赖它，不依赖 `package:rive`。
///
/// 这样既有两个好处：
/// 1. `package:rive` 全库只被本文件 import（R1 风险 6：迁移成本恒为 1 个文件）；
/// 2. 测试可以用假实现验证"点击语义 / 防抖 / 台词 / 升级庆祝"这些**行为契约**，
///    不必真的加载一个 `.riv`（宿主 VM 里 rive_common 的原生库不可用）。
abstract class CharacterRiveController {
  /// 预检：只做"文件在 / 能解析"两件事，不建控制器
  Future<RiveLoadResult> preflight(String rivPath);

  /// 真正挂载的 Rive 叶子（预检通过后才调用）。
  ///
  /// [onFirstFrame] 由叶子在 `onInit` 成功后回调（取消 500ms 超时）；
  /// [onDegrade] 用于"有文件但取不到 main 状态机"这种情况。
  Widget buildLeaf({
    required void Function() onFirstFrame,
    required void Function(RiveFallbackReason reason) onDegrade,
  });

  /// 发一次 `tap` trigger；没有该输入时返回 false（**忽略，不降级**，R5/R7）
  bool fireTap();

  /// `speaking` 布尔输入（气泡出现/消失，R16）；没有该输入时静默忽略
  void setSpeaking(bool value);

  /// `form` 数值输入（1/2/3，进入角色区首帧 + 形态变化后）
  void setForm(int form);

  /// `celebrate` trigger（形态变大那一帧，只发一次，R17）
  void fireCelebrate();

  void dispose();
}

/// **全库唯一** `import 'package:rive/rive.dart'` 的文件。
///
/// 版本锁 `0.13.20`（精确，无 `^`）。0.14.x 起改用 `rive_native`
/// （native assets hook 要从 GitHub 拉预编译库），本机网络已为 sqlite3 打过
/// `hooks.user_defines` 补丁，不再引第二条网络依赖。
///
/// API 落点（0.13.x 的正确用法，不用 `RiveAnimationController`）：
/// - `RiveFile.asset(path, bundle:)` 预检（自动 initialize，抛错即失败）
/// - `RiveAnimation.direct(file, onInit:)` —— **不传 `stateMachines:`**：
///   那个参数会让它自己再造一个 controller，和我们 `fromArtboard` 的重复
///   ⇒ 同一个状态机挂 2 个 controller，直接违反 R11（同屏 ≤1）
/// - `StateMachineController.fromArtboard(artboard, 'main')` + `artboard.addController`
class RiveCharacterAdapter implements CharacterRiveController {
  RiveCharacterAdapter({
    AssetBundle? bundle,
    Duration preflightTimeout = const Duration(seconds: 2),
  })  : _bundle = bundle ?? rootBundle,
        _preflightTimeout = preflightTimeout;

  /// 可注入：测试用假 bundle 造"文件缺失 / 数据损坏"两种情况（R-4）
  final AssetBundle _bundle;

  RiveFile? _file;
  StateMachineController? _sm;

  SMITrigger? _tap;
  SMIBool? _speaking;
  SMINumber? _form;
  SMITrigger? _celebrate;

  bool _disposed = false;

  /// 预检超时：慢说明这设备播不动，直接降级比卡住好。
  /// 可注入只为一件事：测试不必等满 2 秒（产品语义不变）。
  final Duration _preflightTimeout;

  /// 状态机名固定（R5）。名字改了 = 全部降级，这是刻意的（约定优于兼容）。
  static const stateMachineName = 'main';

  @override
  Future<RiveLoadResult> preflight(String rivPath) async {
    try {
      final file =
          await RiveFile.asset(rivPath, bundle: _bundle).timeout(_preflightTimeout);
      _file = file;
      return const RiveLoadResult.ok();
    } on TimeoutException {
      debugPrint('Rive 预检超时（>${_preflightTimeout.inMilliseconds}ms）：$rivPath');
      return const RiveLoadResult.failed(RiveFallbackReason.firstFrameTimeout);
    } catch (e) {
      final reason = reasonOf(e);
      debugPrint('Rive 预检失败（${reason.label}）：$rivPath — $e');
      return RiveLoadResult.failed(reason);
    }
  }

  /// 异常 → 降级原因的映射（纯函数，可单测）
  ///
  /// 分类的唯一目的是让 debug 小字能说清"为什么"，用户侧一律无感。
  static RiveFallbackReason reasonOf(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('unable to load asset') ||
        msg.contains('not found') ||
        msg.contains('no such file') ||
        msg.contains('does not exist')) {
      return RiveFallbackReason.fileMissing;
    }
    if (msg.contains('version')) {
      return RiveFallbackReason.versionUnsupported;
    }
    // 数据损坏、运行时缺原生库（如宿主测试环境的 rive_common_plugin.dll）
    // 都归到这里：对用户来说结果一样 —— 走程序化动画。
    return RiveFallbackReason.parseFailed;
  }

  @override
  Widget buildLeaf({
    required void Function() onFirstFrame,
    required void Function(RiveFallbackReason reason) onDegrade,
  }) {
    final file = _file;
    if (file == null) {
      // 理论上不会走到（预检通过才有 _file），但渲染路径不该有抛异常的分支
      return const SizedBox.shrink();
    }
    return RiveAnimation.direct(
      file,
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
      key: const ValueKey('rive'),
      onInit: (artboard) => _onInit(artboard, onFirstFrame, onDegrade),
    );
  }

  void _onInit(
    Artboard artboard,
    void Function() onFirstFrame,
    void Function(RiveFallbackReason reason) onDegrade,
  ) {
    if (_disposed) return;

    final sm = StateMachineController.fromArtboard(artboard, stateMachineName);
    if (sm == null) {
      debugPrint('Rive 找不到状态机 "$stateMachineName"，降级到程序化动画');
      // onInit 发生在 build 期间：直接回调会在构建中 setState。推迟到帧末。
      SchedulerBinding.instance.addPostFrameCallback((_) {
        onDegrade(RiveFallbackReason.stateMachineMissing);
      });
      return;
    }

    final previous = _sm;
    if (previous != null && previous != sm) {
      // 换文件时先放掉旧的（R11：不允许两个 controller 同时活着）
      previous.dispose();
      RiveControllerBudget.release();
    }

    artboard.addController(sm);
    _sm = sm;
    RiveControllerBudget.acquire();

    // 每个输入单独取、取不到就 null —— 缺输入只是"这个交互做不了"，
    // 不是"这设备播不了"，所以**不降级**（R5）
    _tap = sm.getTriggerInput('tap');
    _speaking = sm.getBoolInput('speaking');
    _form = sm.getNumberInput('form');
    _celebrate = sm.getTriggerInput('celebrate');

    onFirstFrame();
  }

  @override
  bool fireTap() {
    final tap = _tap;
    if (tap == null) return false;
    tap.fire();
    return true;
  }

  @override
  void setSpeaking(bool value) {
    _speaking?.value = value;
  }

  @override
  void setForm(int form) {
    _form?.value = form.toDouble();
  }

  @override
  void fireCelebrate() {
    _celebrate?.fire();
  }

  @override
  void dispose() {
    _disposed = true;
    // 顺序：先从 artboard 摘下（由 controller.dispose 负责），再清引用
    _sm?.dispose();
    if (_sm != null) RiveControllerBudget.release();
    _sm = null;
    _tap = null;
    _speaking = null;
    _form = null;
    _celebrate = null;
    _file = null;
  }
}
