import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/features/settings/data/avatar_storage.dart';

/// 头像存储：拷贝到私有目录 + 删旧文件
///
/// `image_picker` 是插件不能单测；这里覆盖它之后必然要做的两件事。
void main() {
  late Directory docs;
  late Directory src;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('fittrack_docs');
    src = await Directory.systemTemp.createTemp('fittrack_pick');
  });

  tearDown(() async {
    for (final d in [docs, src]) {
      try {
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<File> pick(String name) async {
    final f = File(p.join(src.path, name));
    await f.writeAsBytes([1, 2, 3]);
    return f;
  }

  test('拷贝到 <docs>/avatar/ 下，文件名带时间戳，内容一致', () async {
    final picked = await pick('photo.jpg');
    final path = await copyAvatarToPrivate(
      picked.path,
      docsDir: docs,
      now: DateTime(2025, 3, 5, 10, 30),
    );

    expect(path, isNotNull);
    expect(p.dirname(path!), p.join(docs.path, 'avatar'));
    expect(p.basename(path),
        'avatar_${DateTime(2025, 3, 5, 10, 30).millisecondsSinceEpoch}.jpg');
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('换头像时删掉上一张（避免越攒越多）', () async {
    final first = await copyAvatarToPrivate(
      (await pick('a.jpg')).path,
      docsDir: docs,
      now: DateTime(2025, 3, 5, 10),
    );
    expect(File(first!).existsSync(), isTrue);

    final second = await copyAvatarToPrivate(
      (await pick('b.jpg')).path,
      docsDir: docs,
      now: DateTime(2025, 3, 5, 11),
      previousPath: first,
    );

    expect(second, isNotNull);
    expect(File(first).existsSync(), isFalse, reason: '旧头像必须被删掉');
    expect(File(second!).existsSync(), isTrue);
  });

  test('源文件不存在 → null（调用方提示，不静默存空路径）', () async {
    final path = await copyAvatarToPrivate(
      p.join(src.path, 'nope.jpg'),
      docsDir: docs,
    );
    expect(path, isNull);
  });

  test('删旧头像时绝不删 avatar 目录之外的文件（防止误删相册原图）', () async {
    final outside = File(p.join(src.path, 'original.jpg'));
    await outside.writeAsBytes([9]);

    await deleteAvatarIfUnused(outside.path, keepPath: '/tmp/whatever.jpg');

    expect(outside.existsSync(), isTrue, reason: '只允许删私有 avatar 目录里的副本');
  });

  test('新旧路径相同时不删（否则刚存的头像被自己删掉）', () async {
    final f = await pick('same.jpg');
    final dir = Directory(p.join(docs.path, 'avatar'));
    await dir.create(recursive: true);
    final target = File(p.join(dir.path, 'avatar_1.jpg'));
    await f.copy(target.path);

    await deleteAvatarIfUnused(target.path, keepPath: target.path);

    expect(target.existsSync(), isTrue);
  });
}
