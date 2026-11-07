import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v28：`photos.category`（拍摄角度分类，可空 = 未分类/跳过）
///
/// 三条路径：
///   ① kSchemaVersion = 28；
///   ② v27 → v28：列加上、老照片一条不丢；
///   ③ 重复打开（幂等）：不崩、版本不回退。
void main() {
  test('kSchemaVersion 已推进到 28（v28 = 照片角度分类）', () {
    expect(kSchemaVersion, 28);
  });

  test('v27 → v28：category 列加上、老照片不丢、不新建表', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v28_from27');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');

    final legacy = raw.sqlite3.open(dbFile);
    // v27 的 photos：只有 id/date/file_path/note
    legacy.execute('''
      CREATE TABLE photos (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        note TEXT
      )
    ''');
    legacy.execute(
        "INSERT INTO photos (id, date, file_path, note) VALUES (1, 1700000000000, '/old/photo1.jpg', '第一张')");
    legacy.execute('PRAGMA user_version = 27');
    final tablesBefore = _tables(legacy);
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await db.customSelect('SELECT 1').get();

      expect(await _userVersion(db), 28);
      expect(await _columns(db, 'photos'), contains('category'),
          reason: 'v28 的核心：这一列必须存在');

      final rows = await db
          .customSelect('SELECT file_path, note, category FROM photos')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('file_path'), '/old/photo1.jpg');
      expect(rows.single.read<String?>('note'), '第一张');
      expect(rows.single.read<String?>('category'), isNull,
          reason: '老照片回填 NULL = 未分类（允许跳过）');

      final tablesAfter = await _tableNames(db);
      expect(tablesAfter.length, tablesBefore.length,
          reason: 'v28 只加列，不许新建表');
    } finally {
      await db.close();
    }

    // ③ 幂等：再打开一次不崩、版本仍是 28
    final again = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await again.customSelect('SELECT 1').get();
      expect(await _userVersion(again), 28);
      expect(await _columns(again, 'photos'), contains('category'));
    } finally {
      await again.close();
    }
  });

  test('空库安装：category 可空，默认 NULL', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    try {
      expect(await _columns(db, 'photos'), contains('category'));
      final id = await db.into(db.photos).insert(PhotosCompanion.insert(
            date: DateTime(2026, 11, 7),
            filePath: '/tmp/a.jpg',
          ));
      final row = await (db.select(db.photos)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(row.category, isNull);
    } finally {
      await db.close();
    }
  });
}

// ── 小工具（与其它 migration 测试同口径） ──

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

List<String> _tables(raw.Database db) => db
    .select("SELECT name FROM sqlite_master WHERE type='table'")
    .map((r) => r['name'] as String)
    .toList();
