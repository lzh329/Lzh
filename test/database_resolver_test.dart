import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/services/database_resolver.dart';

void main() {
  group('DbReplacedMarker', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fittrack_db_replaced');
      DbReplacedMarker.clear(baseDir: dir);
    });

    tearDown(() async {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('没有标记时 exists == false（正常启动路径）', () async {
      expect(await DbReplacedMarker.exists(baseDir: dir), isFalse);
    });

    test('write 后 exists == true；内容只是诊断，不参与判定', () async {
      await DbReplacedMarker.write(
        preRestore: '/data/pre-restore-1.sqlite',
        baseDir: dir,
      );
      expect(await DbReplacedMarker.exists(baseDir: dir), isTrue);

      final file = await DbReplacedMarker.markerFile(baseDir: dir);
      final text = await file.readAsString();
      expect(text, contains('pre-restore-1.sqlite'));
    });

    test('write 用原子写：不留 .tmp 残file', () async {
      await DbReplacedMarker.write(baseDir: dir);
      final file = await DbReplacedMarker.markerFile(baseDir: dir);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('clear 后 exists == false（新库打开成功才清）', () async {
      await DbReplacedMarker.write(baseDir: dir);
      await DbReplacedMarker.clear(baseDir: dir);
      expect(await DbReplacedMarker.exists(baseDir: dir), isFalse);
    });

    test('clear 幂等：没有标记时也不抛', () async {
      await DbReplacedMarker.clear(baseDir: dir);
      await DbReplacedMarker.clear(baseDir: dir);
      expect(await DbReplacedMarker.exists(baseDir: dir), isFalse);
    });

    test('标记文件内容损坏也不影响判定（判定只看存在性）', () async {
      final file = await DbReplacedMarker.markerFile(baseDir: dir);
      await file.writeAsString('{ not json');
      expect(
        await DbReplacedMarker.exists(baseDir: dir),
        isTrue,
        reason: '文件坏了不能当成"没换过库"——否则会继续用旧连接',
      );
    });
  });

  group('DatabaseSeal', () {
    tearDown(DatabaseSeal.reset);

    test('默认未封存', () {
      DatabaseSeal.reset();
      expect(DatabaseSeal.sealed, isFalse);
    });

    test('seal / unseal 可切换', () {
      DatabaseSeal.seal();
      expect(DatabaseSeal.sealed, isTrue);
      DatabaseSeal.unseal();
      expect(DatabaseSeal.sealed, isFalse);
    });

    test('异常文案固定（UI 与异常共用同一句，避免两处不一致）', () {
      expect(DatabaseSeal.message, '数据库已被替换，请重启');
    });
  });

  group('DatabaseResolver（单飞 + 失败保留标记）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fittrack_resolver');
      DatabaseSeal.reset();
      DatabaseResolver.resetForTesting();
    });

    tearDown(() async {
      DatabaseSeal.reset();
      DatabaseResolver.resetForTesting();
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('成功：close → reopen → 清标记 → 解除封存', () async {
      await DbReplacedMarker.write(baseDir: dir);
      var closed = 0;
      var opened = 0;

      final ok = await DatabaseResolver.resolve(
        closeCurrent: () async => closed++,
        reopen: () async => opened++,
        markerDir: dir,
      );

      expect(ok, isTrue);
      expect(closed, 1, reason: '必须先关旧实例，否则旧 isolate 泄漏');
      expect(opened, 1);
      expect(await DbReplacedMarker.exists(baseDir: dir), isFalse);
      expect(DatabaseSeal.sealed, isFalse);
    });

    test('失败：保留标记 + 封存（下次启动自然重试，不白屏）', () async {
      await DbReplacedMarker.write(baseDir: dir);

      final ok = await DatabaseResolver.resolve(
        closeCurrent: () async {},
        reopen: () async => throw StateError('boom'),
        markerDir: dir,
      );

      expect(ok, isFalse);
      expect(
        await DbReplacedMarker.exists(baseDir: dir),
        isTrue,
        reason: '标记必须保留，否则下次启动不会重试',
      );
      expect(DatabaseSeal.sealed, isTrue);
    });

    test('close 抛异常不阻断重建（旧实例可能本来就没打开成功）', () async {
      await DbReplacedMarker.write(baseDir: dir);
      var opened = 0;

      final ok = await DatabaseResolver.resolve(
        closeCurrent: () async => throw StateError('already closed'),
        reopen: () async => opened++,
        markerDir: dir,
      );

      expect(ok, isTrue);
      expect(opened, 1);
    });

    test('单飞：连发两次只重建一次', () async {
      await DbReplacedMarker.write(baseDir: dir);
      var opened = 0;
      var release = false;

      Future<void> reopen() async {
        while (!release) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        opened++;
      }

      final first = DatabaseResolver.resolve(
        closeCurrent: () async {},
        reopen: reopen,
        markerDir: dir,
      );
      final second = DatabaseResolver.resolve(
        closeCurrent: () async {},
        reopen: reopen,
        markerDir: dir,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      release = true;
      final results = await Future.wait([first, second]);

      expect(results, [true, true]);
      expect(opened, 1, reason: '连发两次只重建一次：第二次会把刚建好的连接关掉');
    });
  });
}
