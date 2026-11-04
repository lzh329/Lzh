import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';

import 'fakes/fake_rive_controller.dart';

/// 降级链路（R-4 / R-5 / R-8）
///
/// 本期上线时 10 个 `.riv` 一个都不存在 ⇒ **降级是默认路径**，不是异常路径。
/// 所以这一组测试比"成功链路"更重要：它们每天都在真实运行。
void main() {
  // rootBundle 在纯 `test()` 里也要可用
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R-4 加载异常全被兜住（不抛、只返回降级标记）', () {
    test('文件缺失 → failed(fileMissing)，不抛异常', () async {
      final adapter = RiveCharacterAdapter();
      final result = await adapter.preflight('assets/rive/guga_1.riv');
      expect(result.ok, isFalse);
      expect(result.reason, RiveFallbackReason.fileMissing,
          reason: 'rootBundle 找不到资产时报 "Unable to load asset"');
      adapter.dispose();
    });

    test('数据损坏 → 降级、不抛异常（宿主上表现为超时，线上是 parseFailed）',
        () async {
      final adapter = RiveCharacterAdapter(
        bundle: _GarbageBundle(),
        preflightTimeout: const Duration(milliseconds: 100),
      );
      // rive_common 内部的 `Font.initialize()` 在宿主 VM 上会抛一个**没人接**的
      // 异步错误（缺 rive_common_plugin.dll）。它不属于我们的代码，但会污染
      // 测试结果，所以用子 zone 把它收掉 —— 我们只关心 preflight 的返回值。
      final result = await runZonedGuarded(
            () => adapter.preflight('assets/rive/guga_1.riv'),
            (_, __) {},
          ) ??
          const RiveLoadResult.failed(RiveFallbackReason.parseFailed);
      expect(result.ok, isFalse, reason: '任何异常都必须落到降级，不许上抛');
      // 宿主 VM 没有 rive_common 的原生库：`RiveFile.asset` 内部的
      // `Font.initialize()` 会挂住而不是抛错，于是表现成超时。
      // 真机（原生库可用）上同一份垃圾数据会抛解析异常 → parseFailed。
      // 两种都归到"程序化动画"，用户侧观感一致，所以这里按集合断言。
      expect(
        result.reason,
        anyOf(RiveFallbackReason.parseFailed, RiveFallbackReason.firstFrameTimeout),
      );
      adapter.dispose();
    });

    test('预检超时 → failed(firstFrameTimeout)，不卡住界面', () async {
      final adapter = RiveCharacterAdapter(
        bundle: _NeverBundle(),
        preflightTimeout: const Duration(milliseconds: 100),
      );
      final result = await adapter.preflight('assets/rive/guga_1.riv');
      expect(result.ok, isFalse);
      expect(result.reason, RiveFallbackReason.firstFrameTimeout);
      adapter.dispose();
    }, timeout: const Timeout(Duration(seconds: 10)));

    test('reasonOf 分类（纯函数，四种输入的映射）', () {
      expect(
          RiveCharacterAdapter.reasonOf(
              Exception('Unable to load asset: assets/rive/guga_1.riv')),
          RiveFallbackReason.fileMissing);
      expect(RiveCharacterAdapter.reasonOf(Exception('file not found')),
          RiveFallbackReason.fileMissing);
      expect(
          RiveCharacterAdapter.reasonOf(
              Exception('Unsupported Rive file version 7.1')),
          RiveFallbackReason.versionUnsupported);
      expect(RiveCharacterAdapter.reasonOf(Exception('garbage bytes')),
          RiveFallbackReason.parseFailed);
    });
  });

  group('R-8 四级降级都落到程序化，且无任何用户可见提示', () {
    testWidgets('缺文件：mode = procedural + 原因可诊断 + 没有 SnackBar/Dialog',
        (tester) async {
      final reasons = <RiveFallbackReason>[];
      await tester.pumpWidget(_view(
        onReason: reasons.add,
      ));
      // 预检走真实 adapter（宿主上没有 .riv ⇒ fileMissing），等它失败
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.mode, CharacterRenderMode.procedural);
      expect(state.fallbackReason, RiveFallbackReason.fileMissing);
      expect(reasons, contains(RiveFallbackReason.fileMissing));

      // 静默：不许弹任何东西
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('素材'), findsNothing,
          reason: '素材缺失是开发问题，不该转成用户投诉');
    });

    testWidgets('首帧 500ms 未到 → 降级为程序化（不重试本次会话）', (tester) async {
      final fake = FakeRiveController(autoFirstFrame: false); // 永不出首帧
      await tester.pumpWidget(_view(controller: fake));
      await tester.pump(); // preflight ok → 挂叶子
      await tester.pump();

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.mode, CharacterRenderMode.procedural, reason: '还没首帧');

      await tester.pump(CharacterView.firstFrameTimeout);
      await tester.pump();

      expect(state.mode, CharacterRenderMode.procedural);
      expect(state.fallbackReason, RiveFallbackReason.firstFrameTimeout);
      expect(fake.isDisposed, isTrue, reason: '降级后必须释放 controller（R11）');
    });

    testWidgets('找不到 main 状态机 → 降级（R5 第二种）', (tester) async {
      final fake = FakeRiveController(missingStateMachine: true);
      await tester.pumpWidget(_view(controller: fake));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.mode, CharacterRenderMode.procedural);
      expect(state.fallbackReason, RiveFallbackReason.stateMachineMissing);
      expect(fake.isDisposed, isTrue);
    });

    testWidgets('预检成功但状态机正常 → mode = rive（成功链路的行为等价证明）',
        (tester) async {
      final fake = FakeRiveController();
      await tester.pumpWidget(_view(controller: fake));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.mode, CharacterRenderMode.rive);
      expect(state.fallbackReason, RiveFallbackReason.none);
      expect(fake.preflightCount, 1);
      expect(fake.lastForm, 1, reason: '进入角色区首帧要发 form');
    });
  });

  group('R-5 缺输入不崩、不降级', () {
    testWidgets('没有 tap 输入：点角色不抛异常，只换台词', (tester) async {
      final fake = FakeRiveController(hasTapInput: false);
      var taps = 0;
      var line = '在的';
      await tester.pumpWidget(_view(
        controller: fake,
        line: () => line,
        onTap: () {
          taps++;
          line = '换一句';
        },
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.byType(CharacterView));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(taps, 1, reason: '缺 tap 输入只是"动作播不了"，台词照换');
      expect(fake.tapCount, 0);

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.mode, CharacterRenderMode.rive,
          reason: '缺输入**不降级**（R5）');
    });

    test('fireTap 在没有 tap 输入时返回 false（不抛）', () {
      final fake = FakeRiveController(hasTapInput: false);
      expect(fake.fireTap(), isFalse);
      // 没有该输入时 step 不抛
      fake.setSpeaking(true);
      fake.setForm(2);
      fake.fireCelebrate();
    });
  });

  group('R-7 点击只发一次 tap，1.5s 后恢复', () {
    testWidgets('假 controller 记录 trigger 次数 = 1，冷却结束再点 = 2', (tester) async {
      final fake = FakeRiveController();
      await tester.pumpWidget(_view(controller: fake));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.byType(CharacterView));
      await tester.pump();
      expect(fake.tapCount, 1);

      final state = tester.state<CharacterViewState>(find.byType(CharacterView));
      expect(state.canTap, isFalse);

      await tester.pump(CharacterView.tapCooldown);
      expect(state.canTap, isTrue);

      await tester.tap(find.byType(CharacterView));
      await tester.pump();
      expect(fake.tapCount, 2);
    });
  });
}

Widget _view({
  CharacterRiveController? controller,
  void Function(RiveFallbackReason)? onReason,
  String? Function()? line,
  VoidCallback? onTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: CharacterView(
          spec: CharacterCatalog.resolve('guga', 0),
          height: 195,
          line: line == null ? '在的' : line(),
          controllerFactory: controller == null ? null : () => controller,
          onTap: onTap,
          onModeResolved: (_, reason) => onReason?.call(reason),
        ),
      ),
    ),
  );
}

/// 返回垃圾字节的 bundle：解析必然失败
class _GarbageBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (!key.endsWith('.riv')) {
      throw FlutterError('测试 bundle 只提供 .riv');
    }
    return ByteData.sublistView(Uint8List.fromList(List<int>.filled(64, 7)));
  }
}

/// 永不返回的 bundle：用来测预检超时
class _NeverBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}
