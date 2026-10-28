import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/database_health.dart';

Uint8List _header({required int userVersion, bool magic = true}) {
  final bytes = Uint8List(DatabaseFileHealth.minimumHeaderLength);
  if (magic) {
    const text = DatabaseFileHealth.sqliteMagic;
    for (var i = 0; i < text.length; i++) {
      bytes[i] = text.codeUnitAt(i);
    }
  }
  ByteData.sublistView(
    bytes,
    DatabaseFileHealth.userVersionOffset,
    DatabaseFileHealth.userVersionOffset + 4,
  ).setUint32(0, userVersion, Endian.big);
  return bytes;
}

void main() {
  group('parseUserVersion（纯函数：读文件头 offset 60 的 4 字节大端）', () {
    test('正常解析 20 / 21', () {
      expect(DatabaseFileHealth.parseUserVersion(_header(userVersion: 20)), 20);
      expect(DatabaseFileHealth.parseUserVersion(_header(userVersion: 21)), 21);
    });

    test('大端序：0x00000102 解析为 258 而不是 16908288', () {
      final bytes = _header(userVersion: 0x00000102);
      expect(DatabaseFileHealth.parseUserVersion(bytes), 258);
    });

    test('魔数不对 → null（不是 SQLite 文件）', () {
      expect(
        DatabaseFileHealth.parseUserVersion(
            _header(userVersion: 20, magic: false)),
        isNull,
      );
    });

    test('长度不足 64 字节 → null', () {
      expect(
        DatabaseFileHealth.parseUserVersion(
          Uint8List.fromList(List.filled(10, 0)),
        ),
        isNull,
      );
    });
  });

  group('readUserVersion（真实文件）', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('fittrack_health');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('文件不存在 → null', () async {
      final file = File(p.join(dir.path, 'nope.sqlite'));
      expect(await DatabaseFileHealth.readUserVersion(file), isNull);
    });

    test('不是 SQLite 的垃圾文件 → null', () async {
      final file = File(p.join(dir.path, 'garbage.sqlite'));
      await file.writeAsBytes(List.filled(200, 65)); // 'A' × 200
      expect(await DatabaseFileHealth.readUserVersion(file), isNull);
    });

    test('真实 drift 库 → 读到当前 schemaVersion', () async {
      final file = File(p.join(dir.path, 'real.sqlite'));
      final db = AppDatabase.withExecutor(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();

      expect(
        await DatabaseFileHealth.readUserVersion(file),
        kSchemaVersion,
        reason: '文件头 user_version 必须等于 AppDatabase.schemaVersion',
      );
    });
  });

  group('judgeMarker（纯函数：僵尸 marker 三态判定）', () {
    test('user_version == schemaVersion → zombie（迁移其实成功了）', () {
      expect(
        judgeMarker(userVersion: 20, schemaVersion: 20),
        MarkerVerdict.zombie,
      );
    });

    test('user_version < schemaVersion → genuine（真失败）', () {
      expect(
        judgeMarker(userVersion: 19, schemaVersion: 20),
        MarkerVerdict.genuine,
      );
      expect(
        judgeMarker(userVersion: 0, schemaVersion: 20),
        MarkerVerdict.genuine,
      );
    });

    test('user_version > schemaVersion → newerData（绝不能当僵尸删掉）', () {
      expect(
        judgeMarker(userVersion: 21, schemaVersion: 20),
        MarkerVerdict.newerData,
        reason: '用户装过更新版本又装回旧版，删 marker 会把版本号写回旧值',
      );
    });

    test('读不出来（null）→ genuine，宁可多给一次重试也不假装健康', () {
      expect(
        judgeMarker(userVersion: null, schemaVersion: 20),
        MarkerVerdict.genuine,
      );
    });
  });
}
