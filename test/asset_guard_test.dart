import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_catalog.dart';

/// 素材守卫（R-3 / R-13 / C-16）
///
/// 素材缺失是**打包/开发问题**，不是用户操作问题 —— 所以它必须在这里被拦下，
/// 而不是在用户面前弹「素材加载失败」（决策 8：用户能做的只有重装，而重装 = 数据全丢）。
///
/// 这个测试只读文件头，不解码图片：CI 上跑得快，也不会因为缺 `dart:ui` 绑定而挂。
void main() {
  group('R-3 pubspec 声明的是目录，不是逐个文件', () {
    late String pubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
    });

    test('两个目录都声明了', () {
      expect(pubspec, contains('- assets/characters/'));
      expect(pubspec, contains('- assets/rive/'));
    });

    test('没有逐文件声明 .riv / 新角色 PNG（否则加文件要改 pubspec，违反"替换即生效"）', () {
      final assetLines = pubspec
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('- assets/'))
          .toList();
      for (final line in assetLines) {
        expect(line.endsWith('.riv'), isFalse, reason: '不许逐文件声明 .riv：$line');
        expect(line.contains('characters/nuonuo'), isFalse);
        expect(line.contains('characters/phoebe'), isFalse);
      }
    });

    test('两个目录都非空（空目录会让构建报 unable to find directory entry）', () {
      for (final dir in ['assets/characters', 'assets/rive']) {
        final entries = Directory(dir).listSync();
        expect(entries, isNotEmpty, reason: '$dir 是空目录，flutter build 会直接失败');
      }
    });

    test('assets/rive/ 本轮不含任何 .riv —— 官方示例不进生产资产', () {
      final rivs = Directory('assets/rive')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.riv'))
          .toList();
      expect(rivs, isEmpty,
          reason: '首页出现别人的素材比不接 Rive 更糟；链路验证用 test/fixtures/ 里的夹具');
      expect(File('assets/rive/PROVENANCE.md').existsSync(), isTrue,
          reason: '这个文件承担"目录非空"职责，删了构建就炸');
    });
  });

  group('C-16 注册表里声明的立绘都存在', () {
    test('7 个立绘路径（3 咕嘎 + 3 糯糯 + 1 菲比）全部落在磁盘上', () {
      for (final def in CharacterCatalog.all) {
        for (final form in def.forms) {
          if (form.imageAsset != null) {
            expect(File(form.imageAsset!).existsSync(), isTrue,
                reason: '${def.name} form ${form.form} 立绘缺失：${form.imageAsset}');
          }
        }
      }
    });

    test('咕嘎的分层拆图（_head / _body）都存在', () {
      for (final form in CharacterCatalog.guga.forms) {
        expect(form.hasSplit, isTrue);
        expect(File(form.headAsset!).existsSync(), isTrue);
        expect(File(form.bodyAsset!).existsSync(), isTrue);
      }
    });

    test('路径没有代码拼接痕迹：注册表里出现的都是真实文件的完整路径', () {
      for (final def in CharacterCatalog.all) {
        for (final form in def.forms) {
          final asset = form.imageAsset;
          if (asset == null) continue;
          expect(asset.contains('{'), isFalse);
          expect(asset.endsWith('.png'), isTrue);
        }
      }
    });
  });

  group('R-13 新素材红线（只卡 assets/characters/，老素材不动）', () {
    test('长边 ≤1200px、单张 ≤400KB、单角色三形态合计 ≤1.2MB', () {
      const maxEdge = 1200;
      const maxBytes = 400 * 1024;
      const maxCharBytes = 1258291; // 1.2 MB

      final files = Directory('assets/characters')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList();
      expect(files, isNotEmpty);

      final bytesByCharacter = <String, int>{};
      for (final f in files) {
        final size = f.lengthSync();
        final dims = _pngSize(f.readAsBytesSync());
        expect(dims.$1 <= maxEdge && dims.$2 <= maxEdge, isTrue,
            reason: '${f.path} 长边 ${dims.$1}x${dims.$2} 超 1200 —— '
                '立绘只显示 195 逻辑像素，再大是给不存在的高分屏准备');
        expect(size <= maxBytes, isTrue,
            reason: '${f.path} ${(size / 1024).round()}KB 超 400KB');

        final name = f.uri.pathSegments.last;
        final character = name.split('_').first;
        bytesByCharacter[character] = (bytesByCharacter[character] ?? 0) + size;
      }

      bytesByCharacter.forEach((character, total) {
        expect(total <= maxCharBytes, isTrue,
            reason: '$character 三形态合计 ${(total / 1024).round()}KB 超 1.2MB');
      });
    });

    test('新增素材总量 ≤3MB（7 张 PNG 的上限）', () {
      final total = Directory('assets/characters')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .fold<int>(0, (sum, f) => sum + f.lengthSync());
      expect(total <= 3 * 1024 * 1024, isTrue,
          reason: '本轮新增 ${(total / 1024).round()}KB，红线 3MB');
    });
  });

  group('文件名契约（主理人正在重做抠图，会原位替换）', () {
    test('4 张图文件名逐字固定，改名会让注册表与素材失联', () {
      const expected = [
        'assets/characters/nuonuo_1.png',
        'assets/characters/nuonuo_2.png',
        'assets/characters/nuonuo_3.png',
        'assets/characters/phoebe_1.png',
      ];
      for (final path in expected) {
        expect(File(path).existsSync(), isTrue, reason: '缺 $path');
      }
      final registered = <String>{
        for (final def in CharacterCatalog.all)
          for (final form in def.forms)
            if (form.imageAsset != null &&
                form.imageAsset!.startsWith('assets/characters/'))
              form.imageAsset!,
      };
      expect(registered, expected.toSet());
    });
  });
}

/// 读 PNG 头拿宽高（IHDR 固定在 offset 16..24）
(int, int) _pngSize(Uint8List bytes) {
  // PNG 签名 8 字节 + 长度 4 + 'IHDR' 4 + width 4 + height 4
  expect(bytes.length, greaterThan(24));
  expect(bytes.sublist(1, 4), equals(ascii.encode('PNG')));
  final data = ByteData.sublistView(bytes, 16, 24);
  return (data.getUint32(0), data.getUint32(4));
}
