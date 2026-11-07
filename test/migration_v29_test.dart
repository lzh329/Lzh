import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v29：`user_settings.countdown_voice_mode`（倒计时朗读模式，可空）
///
/// 可空 = 未设置 → 按历史行为（321 版，只读最后 3 秒）。
void main() {
  test('kSchemaVersion 已推进到 29（v29 = 倒计时朗读模式）', () {
    expect(kSchemaVersion, 29);
  });

  test('v28 → v29：列加上、老设置不丢、不新建表', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v29_from28');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');

    final legacy = raw.sqlite3.open(dbFile);
    legacy.execute('''
      CREATE TABLE user_settings (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        nickname TEXT,
        tts_voice TEXT
      )
    ''');
    legacy.execute(
        "INSERT INTO user_settings (id, nickname, tts_voice) VALUES (1, '小嘎', 'zh-cn-xiaoxiao')");
    legacy.execute('PRAGMA user_version = 28');
    final tablesBefore = _tables(legacy);
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await db.customSelect('SELECT 1').get();

      expect(await _userVersion(db), 29);
      expect(await _columns(db, 'user_settings'),
          contains('countdown_voice_mode'),
          reason: 'v29 的核心：这一列必须存在');

      final rows = await db
          .customSelect(
              'SELECT nickname, tts_voice, countdown_voice_mode FROM user_settings')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String?>('nickname'), '小嘎');
      expect(rows.single.read<String?>('tts_voice'), 'zh-cn-xiaoxiao');
      expect(rows.single.read<String?>('countdown_voice_mode'), isNull,
          reason: '老用户回填 NULL = 保持历史行为（321 版）');

      final tablesAfter = await _tableNames(db);
      expect(tablesAfter.length, tablesBefore.length, reason: 'v29 只加列');
    } finally {
      await db.close();
    }

    final again = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    try {
      await again.customSelect('SELECT 1').get();
      expect(await _userVersion(again), 29);
      expect(
          await _columns(again, 'user_settings'), contains('countdown_voice_mode'));
    } finally {
      await again.close();
    }
  });

  test('空库安装：countdown_voice_mode 可空，默认 NULL', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    try {
      expect(
          await _columns(db, 'user_settings'), contains('countdown_voice_mode'));
      await db.into(db.userSettings).insert(const UserSettingsCompanion());
      final row = await db.select(db.userSettings).getSingle();
      expect(row.countdownVoiceMode, isNull);
    } finally {
      await db.close();
    }
  });
}

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
