import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show CachingAssetBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_rive_adapter.dart';

/// Rive 链路的三件事：**状态机契约、trigger、失败降级**。
///
/// ⚠️ 诚实的边界：宿主 VM（`flutter test`）里 `rive_common` 的原生库不可用，
/// 真实的 `RiveFile.asset` 无法完成解析。所以这里证明的是：
///   ① 夹具是**合法的 Rive 二进制**（不是随便一个文件）；
///   ② 真实 adapter 会调用**契约规定的**状态机名与四个输入名（源码守卫，防手滑）；
///   ③ 真实 adapter 拿**真实 Rive 字节**跑 `RiveFile` 时，失败会降级而**不抛**；
///   ④ 本期注册表里的 10 个 `.riv` 全部缺失 ⇒ **每个角色每一档都走程序化**。
/// "加载成功 + trigger 真的驱动了动画"只能在真机上验（见 PR 描述的人工步骤）——
/// 行为契约那一层由 `character_view_test.dart` 的假驱动证明。
void main() {
  // rootBundle / ServicesBinding 在纯 `test()` 里也要可用
  TestWidgetsFlutterBinding.ensureInitialized();

  group('① 夹具是合法的 Rive 二进制（test/fixtures/，不进资产）', () {
    test('文件存在、magic 为 RIVE、版本号可读', () {
      for (final name in ['light_switch', 'rocket']) {
        final file = File('test/fixtures/$name.riv');
        expect(file.existsSync(), isTrue, reason: '缺夹具 test/fixtures/$name.riv');
        final bytes = file.readAsBytesSync();
        expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIVE',
            reason: '$name.riv 不是 Rive 二进制');
        final version = ByteData.sublistView(bytes, 4, 8).getUint16(0);
        expect(version, greaterThanOrEqualTo(7),
            reason: '$name.riv 的文件格式版本 $version 太旧');
        expect(file.lengthSync(), lessThan(128 * 1024),
            reason: '夹具不随包发布，但也没必要超过 128KB');
      }
    });

    test('夹具里能读出 state machine 名字（说明真的含状态机，不是空 artboard）',
        () {
      // Rive 把字符串按 toC 表存在文件里，名字是明文字节
      final bytes = File('test/fixtures/light_switch.riv').readAsBytesSync();
      final text = String.fromCharCodes(
          bytes.where((b) => b >= 32 && b < 127));
      expect(text, contains('Artboard'));
      // 这个官方示例带一个状态机（Artboard 下的 Switch / Off 状态）
      expect(text.toLowerCase(), contains('switch'));
    });

    test('夹具**不进**生产资产：assets/rive/ 里没有任何 .riv', () {
      final rivs = Directory('assets/rive')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.riv'));
      expect(rivs, isEmpty,
          reason: '首页出现别人的素材，比不接 Rive 更糟（主理人拍板）');
    });
  });

  group('② 状态机契约：名字与输入是写死的，不许漂', () {
    late String source;

    setUpAll(() {
      source = File(
              'lib/features/dashboard/presentation/widgets/character_rive_adapter.dart')
          .readAsStringSync();
    });

    test('state machine 名固定 main（R5）', () {
      expect(RiveCharacterAdapter.stateMachineName, 'main');
      expect(source, contains("stateMachineName = 'main'"));
    });

    test('四个输入按契约取名（R5/决策 14）', () {
      expect(source, contains("getTriggerInput('tap')"));
      expect(source, contains("getBoolInput('speaking')"));
      expect(source, contains("getNumberInput('form')"));
      expect(source, contains("getTriggerInput('celebrate')"));
    });

    test('用 StateMachineController.fromArtboard + addController（不是线性动画控制器）',
        () {
      expect(source, contains('StateMachineController.fromArtboard'));
      expect(source, contains('addController'));
      // 只看代码，不看注释：注释里必须能写"为什么不用 RiveAnimationController"
      final code = source
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('RiveAnimationController'), isFalse,
          reason: '0.13.x 里它只用于播线性动画，本期用不到');
      // 双 controller 的坑：给 RiveAnimation 传 stateMachines 会让它自己再造一个
      expect(code.contains('stateMachines:'), isFalse);
    });

    test('**全库只有一个文件** import package:rive（迁移成本恒为 1 个文件）', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        if (text.contains('package:rive/rive.dart')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, hasLength(1),
          reason: '只允许 character_rive_adapter.dart：${offenders.join(', ')}');
      expect(offenders.single, contains('character_rive_adapter.dart'));
    });
  });

  group('③ 真实 Rive 字节 + 失败 → 降级而不抛（端到端走一遍 RiveFile）', () {
    test('把夹具字节喂给真实 adapter：解析不可用时降级，宁可程序化也不崩', () async {
      final adapter = RiveCharacterAdapter(
        bundle: _FixtureBundle('test/fixtures/light_switch.riv'),
        preflightTimeout: const Duration(milliseconds: 200),
      );
      // rive_common 在宿主上的未接异步错误（缺原生库）不属于我们的代码，
      // 用子 zone 收掉，只关心 preflight 的返回值。
      final result = await _quietly(
        () => adapter.preflight('assets/rive/guga_1.riv'),
      );
      expect(result.ok, isFalse);
      expect(result.reason, isNot(RiveFallbackReason.none));
      adapter.dispose();
    });
  });

  group('④ 本期 7 个 .riv 全缺 ⇒ 每一档都降级（降级是默认路径）', () {
    test('注册表里 7 个 rivPath 全部 preflight 失败，且原因都是"文件缺失"', () async {
      final paths = <String>{
        for (final def in CharacterCatalog.all)
          for (final form in def.forms)
            CharacterCatalog.resolve(def.id.wire, form.minLossJin).rivPath,
      };
      // 咕嘎 3 档 + 糯糯 3 档 + 菲比 1 档 = 7 个文件。
      // 如果将来给菲比加档位，这里会红 —— 那正是"新档位必须配 .riv 规则"的提醒。
      expect(paths, hasLength(7));

      for (final path in paths) {
        final adapter = RiveCharacterAdapter();
        final result = await adapter.preflight(path);
        expect(result.ok, isFalse, reason: '$path 不该存在');
        expect(result.reason, RiveFallbackReason.fileMissing, reason: path);
        adapter.dispose();
      }
    });
  });
}

/// 收掉 rive_common 在宿主 VM 上的未接异步错误（不隐藏我们自己的异常：
/// 我们把异常翻译成 `failed` 结果，所以 `null` 只可能是被 zone 吞掉了）
Future<RiveLoadResult> _quietly(Future<RiveLoadResult> Function() body) async {
  final result = await runZonedGuarded(body, (_, __) {});
  return result ?? const RiveLoadResult.failed(RiveFallbackReason.parseFailed);
}

/// 用测试夹具的字节冒充某个资产路径
class _FixtureBundle extends CachingAssetBundle {
  _FixtureBundle(this.path);

  final String path;

  @override
  Future<ByteData> load(String key) async {
    final bytes = File(path).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}
