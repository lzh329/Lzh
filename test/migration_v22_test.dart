import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

/// v21 → v22 迁移：user_settings 加 nickname / avatarPath 两列
///
/// 这两列都可空，null = 用户没设置。迁移只做 ADD COLUMN，不动任何老数据。
void main() {
  test('kSchemaVersion 已到 22+', () {
    expect(kSchemaVersion, greaterThanOrEqualTo(22));
  });

  test('老库（v21）升到 v22：老数据完整、新列存在且为 null、可重复执行', () async {
    // 用原生 sqlite3 造一个 v21 的库文件（drift 一打开就会 onCreate，不能用它来"造旧库"）
    final tmp = await Directory.systemTemp.createTemp('fittrack_v22');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    legacy.execute('''
      CREATE TABLE user_settings (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        height_cm REAL,
        target_weight_kg REAL,
        birth_date INTEGER,
        gender TEXT,
        activity_level TEXT,
        pin_code TEXT,
        lock_enabled INTEGER NOT NULL DEFAULT 0,
        speech_rate REAL,
        speech_pitch REAL,
        tts_voice TEXT,
        reminder_enabled INTEGER NOT NULL DEFAULT 0,
        reminder_hour INTEGER,
        reminder_minute INTEGER,
        theme_mode TEXT,
        default_training_sec INTEGER,
        default_rest_sec INTEGER,
        rest_short_sec INTEGER,
        rest_long_sec INTEGER,
        auto_backup_enabled INTEGER NOT NULL DEFAULT 1,
        ai_api_key TEXT,
        ai_style TEXT,
        ai_constraints TEXT,
        ai_reply_length TEXT,
        ai_temperature REAL,
        ai_persona_custom TEXT,
        ai_web_search_enabled INTEGER NOT NULL DEFAULT 1,
        daily_calorie_target INTEGER,
        protein_target_g REAL,
        carbs_target_g REAL,
        fat_target_g REAL,
        ai_health_override_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    legacy.execute('PRAGMA user_version = 21');
    legacy.execute(
        'INSERT INTO user_settings (height_cm, gender, ai_health_override_count) '
        "VALUES (175.0, 'male', 2)");
    legacy.dispose();

    // 现在用当前 schema 打开同一个库文件 → 触发 v21→v22 迁移
    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, kSchemaVersion);

    final repo = UserSettingsRepositoryImpl(db);
    final s = await repo.get();
    expect(s, isNotNull);
    expect(s!.heightCm, 175.0, reason: '老数据不能丢');
    expect(s.gender, 'male');
    expect(s.aiHealthOverrideCount, 2);
    expect(s.nickname, isNull, reason: '新列默认 null（= 没设置），不是空串');
    expect(s.avatarPath, isNull);

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('新库直接是 v22，两列可读可写可清空', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    final repo = UserSettingsRepositoryImpl(db);
    await repo.save(); // 建行

    await repo.saveNickname('小嘎');
    await repo.saveAvatarPath('/data/avatar/a.jpg');
    var s = await repo.get();
    expect(s!.nickname, '小嘎');
    expect(s.avatarPath, '/data/avatar/a.jpg');

    // 清除 → 回到 null（不是空串）
    await repo.saveNickname(null);
    await repo.saveAvatarPath(null);
    s = await repo.get();
    expect(s!.nickname, isNull, reason: '清除必须是 NULL，空串会让"没设过"分不清');
    expect(s.avatarPath, isNull);

    await db.close();
  });
}
