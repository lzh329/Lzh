import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v27：`user_settings.tts_config`（云端音色 MiniMax，整块 JSON 一列）
///
/// 三条路径：
///   ① kSchemaVersion = 27；
///   ② v26 → v27：列加上、老行原样、只加列不建表；
///   ③ 重复打开（幂等）：不崩、版本不回退。
void main() {
  test('kSchemaVersion 已推进到 27（v27 = 云端音色 tts_config）', () {
    expect(kSchemaVersion, 27);
  });

  test('v26 → v27：tts_config 列加上、老设置一条不丢、不新建表', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v27_from26');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');

    final legacy = raw.sqlite3.open(dbFile);
    // v26 的 user_settings（只建本次迁移用得到的列，迁移只做 ADD COLUMN）
    legacy.execute('''
      CREATE TABLE user_settings (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        nickname TEXT,
        tts_voice TEXT,
        ai_provider_id TEXT
      )
    ''');
    legacy.execute(
        "INSERT INTO user_settings (id, nickname, tts_voice) VALUES (1, '小嘎', 'zh-cn-xiaoxiao')");
    legacy.execute('PRAGMA user_version = 26');
    final tablesBefore = _tables(legacy);
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await db.customSelect('SELECT 1').get();

      expect(await _userVersion(db), 27);
      expect(await _columns(db, 'user_settings'), contains('tts_config'),
          reason: 'v27 的核心：这一列必须存在');

      // 老数据一条不丢（昵称 / 系统音色都还在）
      final rows = await db
          .customSelect('SELECT nickname, tts_voice, tts_config FROM user_settings')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('nickname'), '小嘎');
      expect(rows.single.read<String?>('tts_voice'), 'zh-cn-xiaoxiao');
      expect(rows.single.read<String?>('tts_config'), isNull,
          reason: '老行回填 NULL = 用系统音色（默认行为不变）');

      // 只加列不建表
      final tablesAfter = await _tableNames(db);
      expect(tablesAfter.where((t) => t.startsWith('voice')), isEmpty);
      expect(tablesAfter.length, tablesBefore.length,
          reason: 'v27 不许新建表');
    } finally {
      await db.close();
    }

    // ③ 幂等：再打开一次不崩、版本仍是 27
    final again = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await again.customSelect('SELECT 1').get();
      expect(await _userVersion(again), 27);
      expect(await _columns(again, 'user_settings'), contains('tts_config'));
    } finally {
      await again.close();
    }
  });

  test('空库安装：tts_config 列存在且可空（默认 NULL = 系统音色）', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    try {
      expect(await _columns(db, 'user_settings'), contains('tts_config'));
      await db.into(db.userSettings).insert(const UserSettingsCompanion());
      final row = await db.select(db.userSettings).getSingle();
      expect(row.ttsConfig, isNull);
    } finally {
      await db.close();
    }
  });
}

// ── 小工具（与其它 migration 测试同口径，避免依赖 drift 的元数据 API） ──

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
