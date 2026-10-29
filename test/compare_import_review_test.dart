import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/features/body_log/presentation/widgets/compare_import.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_review_launcher.dart';

void main() {
  group('buildPhotoImportArgs（选中文件 → addPhoto 的参数）', () {
    test('日期取导入当天 0 点，note 标出来源是相册', () {
      final args = buildPhotoImportArgs(
        File('/tmp/picked.jpg'),
        now: DateTime(2025, 3, 5, 21, 40),
      );
      expect(args.date, DateTime(2025, 3, 5), reason: '不带时分秒');
      expect(args.imageFile.path, '/tmp/picked.jpg');
      expect(args.note, '相册导入', reason: '要能区分"今天拍的"和"从相册翻出来的"');
    });
  });

  group('resolveInitialImage（外部带进来的初始图片）', () {
    test('null / 空串 → null', () {
      expect(resolveInitialImage(null), isNull);
      expect(resolveInitialImage(''), isNull);
    });

    test('文件不存在 → null（不硬造 File，避免发送时才崩）', () {
      expect(
        resolveInitialImage('/no/such/file.png', exists: (_) => false),
        isNull,
      );
    });

    test('文件存在 → 返回该 File', () {
      final f = resolveInitialImage('/tmp/x.png', exists: (_) => true);
      expect(f, isNotNull);
      expect(f!.path, '/tmp/x.png');
    });
  });

  group('writeCompareSnapshot（截图 PNG → 临时文件）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fittrack_cmp_test');
    });

    tearDown(() async {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('写入指定目录，返回的文件内容与传入字节一致', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final file = await writeCompareSnapshot(
        bytes,
        dir: dir,
        now: DateTime(2025, 3, 5, 10),
      );
      expect(file.existsSync(), isTrue);
      expect(await file.readAsBytes(), bytes);
      expect(p.basename(file.path), startsWith('fittrack_compare_'));
      expect(p.extension(file.path), '.png');
    });

    test('只保留最新一张：旧快照被清掉，避免临时目录膨胀', () async {
      final old = File(p.join(dir.path, 'fittrack_compare_1.png'));
      await old.writeAsBytes([9]);

      final latest = await writeCompareSnapshot(
        Uint8List.fromList([1]),
        dir: dir,
        now: DateTime(2025, 3, 5, 11),
      );

      expect(old.existsSync(), isFalse, reason: '旧截图没有复用价值，应清掉');
      expect(latest.existsSync(), isTrue);
    });

    test('同类目录里的无关文件不被动', () async {
      final keep = File(p.join(dir.path, 'unrelated.txt'));
      await keep.writeAsString('x');

      await writeCompareSnapshot(Uint8List.fromList([1]), dir: dir);

      expect(keep.existsSync(), isTrue);
    });
  });
}
