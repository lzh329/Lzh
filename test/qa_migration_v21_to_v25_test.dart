import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// QA 补充：**v21 → v25 全链**（C-2 / C-3 的升级路径）。
///
/// 已有测试只覆盖单段（v21→v24、v24→v25）。真实用户里最危险的是"跨了四个版本
/// 没更新"的那批：v22 加两列、v23 合并分类、v24 两张表 + 两列 + 一列 chips、
/// v25 加 character_id —— 中间任何一步依赖"上一步刚建的列"都会在这一条上炸。
///
/// 断言三件事：版本号收敛到 25、`character_id` 的 `dflt_value` 是 `'guga'`、
/// 老数据一个字节都没被动过。
void main() {
  test('v21 老库一路升到 v25：不抛、老数据完整、character_id 默认 guga', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v25_from21');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV21Schema(legacy);
    legacy.execute(
        "INSERT INTO user_settings (id, gender, height_cm) VALUES (1, 'female', 165)");
    legacy.execute(
        "INSERT INTO exercises (id, name, category) VALUES (1, '深蹲', 'bodyweight'), (2, '跳绳', 'cardio')");
    legacy.execute(
        "INSERT INTO workout_templates (id, name, difficulty, focus) VALUES (1, '燃脂', '中阶', '全身')");
    legacy.execute(
        'INSERT INTO workout_template_items (template_id, exercise_id) VALUES (1, 2)');
    legacy.execute(
        "INSERT INTO ai_chat_messages (id, role, content) VALUES (1, 'user', '今天练什么')");
    legacy.execute('PRAGMA user_version = 21');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    addTearDown(db.close);

    // 打开即触发 onUpgrade：这里抛异常就是"启动即死"
    await db.customSelect('SELECT 1').get();

    // ① 版本号收敛
    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first as int;
    expect(version, kSchemaVersion);

    // ② v25 的列在，且 DDL 默认值就是 'guga'（不是代码里补的）
    final info = await _columnInfo(db, 'user_settings', 'character_id');
    expect(info.$1, "'guga'", reason: "dflt_value 必须是 'guga'");
    expect(info.$2, isTrue, reason: 'NOT NULL');

    // ③ 跨版本新增的其它列也在（防止某一版块被跳过）
    final settingsColumns =
        await _columns(db, 'user_settings');
    expect(settingsColumns,
        containsAll(['nickname', 'avatar_path', 'character_id']));
    expect(await _columns(db, 'ai_chat_messages'), contains('chips'));
    expect(await _tableNames(db),
        containsAll(['coach_memories', 'coach_proactive_messages']));

    // ④ 老数据一条不少
    final settings = await db
        .customSelect('SELECT gender, height_cm FROM user_settings WHERE id = 1')
        .getSingle();
    expect(settings.data['gender'], 'female');
    expect(settings.data['height_cm'], 165);
    final chat = await db
        .customSelect('SELECT content FROM ai_chat_messages WHERE id = 1')
        .getSingle();
    expect(chat.data['content'], '今天练什么');
    // 老行读 character_id → 默认值
    final charRow = await db
        .customSelect('SELECT character_id FROM user_settings WHERE id = 1')
        .getSingle();
    expect(charRow.data['character_id'], 'guga');
  });

  // 备注：另有一条「v21 库连 user_settings 表都没有」的合成场景，实测会在
  // **v22 块**（`addColumn:nickname`）抛 no such table —— 那属于既有迁移代码的
  // 健壮性缺口，且生产上不存在（user_settings 自 v1 起就有），不计入本期缺陷。
}

/// v21 的最小可用结构：**没有** v22 的 nickname/avatar_path，
/// 也没有 v23/v24/v25 的任何东西
void _createV21Schema(raw.Database db) {
  db.execute('''
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
  db.execute('''
    CREATE TABLE exercises (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      muscle_group TEXT,
      default_reps INTEGER,
      default_duration_sec INTEGER,
      is_custom INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE workout_templates (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      difficulty TEXT NOT NULL,
      focus TEXT NOT NULL,
      minutes INTEGER NOT NULL DEFAULT 15,
      description TEXT,
      accent_key TEXT NOT NULL DEFAULT 'green',
      is_recommended INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
  db.execute('''
    CREATE TABLE workout_template_items (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL,
      exercise_id INTEGER NOT NULL,
      "order" INTEGER NOT NULL DEFAULT 0,
      target_sets INTEGER NOT NULL DEFAULT 3,
      target_reps INTEGER,
      target_duration_sec INTEGER,
      rest_sec INTEGER
    )
  ''');
  db.execute('''
    CREATE TABLE ai_chat_messages (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      role TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

/// (dflt_value, notnull)
Future<(String?, bool)> _columnInfo(
    AppDatabase db, String table, String column) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  for (final r in rows) {
    if (r.read<String>('name') == column) {
      return (
        r.data['dflt_value'] as String?,
        (r.data['notnull'] as num).toInt() == 1,
      );
    }
  }
  throw StateError('列不存在: $table.$column');
}
