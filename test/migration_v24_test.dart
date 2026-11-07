import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v24：教练主动消息 + 结构化记忆 + 两个开关列 + 芯片列
///
/// 覆盖四条升级路径（PRD 7.4(5) / playbook 7.7）：
///   ① 空库安装（onCreate → createAll）
///   ② v23 → v24
///   ③ v21 → v24（v22 + v23 + v24 全链）
///   ④ 半迁移现场重跑（DDL 已落盘但 user_version 没推进）
///
/// 用原生 sqlite3 造老库（drift 一打开就 onCreate，造不出旧库）。
void main() {
  test('kSchemaVersion 已推进到 26', () {
    expect(kSchemaVersion, 28);
  });

  test('空库安装：两张新表 + 三个新列 + 一条新索引都在，唯一约束由 CREATE TABLE 落地', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    expect(await _tableNames(db), containsAll([
      'coach_memories',
      'coach_proactive_messages',
    ]));

    // 三个新列
    expect(await _columns(db, 'user_settings'),
        containsAll(['coach_memory_enabled', 'coach_proactive_enabled']));
    expect(await _columns(db, 'ai_chat_messages'), contains('chips'));

    // 普通索引（迁移侧 kV24Indexes 与 @TableIndex 两处定义）
    expect(await _indexNames(db),
        contains('idx_coach_proactive_created_at'));

    // 唯一约束：dedupe_key 只有一个索引（sqlite_autoindex），不额外建命名索引
    final dedupeIndexes = (await _indexNames(db))
        .where((n) => n.contains('coach_proactive'))
        .toList();
    expect(dedupeIndexes.where((n) => n.startsWith('sqlite_autoindex')),
        hasLength(1),
        reason: 'dedupe_key 的唯一性由 CREATE TABLE ... UNIQUE 表达，只有自动索引');
    expect(dedupeIndexes.where((n) => n.contains('dedupe')), isEmpty,
        reason: '不许再建命名唯一索引：两个索引维护同一列只是写放大');

    await db.close();
  });

  test('v23 → v24：只多 2 表 3 列 1 索引，老数据一条不丢', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v24_from23');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV23UserSettings(legacy);
    legacy.execute('''
      CREATE TABLE ai_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    legacy.execute("INSERT INTO user_settings (id, nickname) VALUES (1, '小嘎')");
    legacy.execute(
        "INSERT INTO ai_chat_messages (role, content) VALUES ('user', '你好'), ('assistant', '在的')");
    legacy.execute('PRAGMA user_version = 23');    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    expect(await _userVersion(db), kSchemaVersion);
    expect(await _tableNames(db), containsAll([
      'coach_memories',
      'coach_proactive_messages',
    ]));
    expect(await _columns(db, 'user_settings'),
        containsAll(['coach_memory_enabled', 'coach_proactive_enabled']));
    expect(await _columns(db, 'ai_chat_messages'), contains('chips'));
    expect(await _indexNames(db), contains('idx_coach_proactive_created_at'));

    // 老数据一条不丢
    final nickname = await db
        .customSelect('SELECT nickname FROM user_settings WHERE id = 1')
        .getSingle();
    expect(nickname.data['nickname'], '小嘎');
    final chat = await db
        .customSelect('SELECT COUNT(*) AS c FROM ai_chat_messages')
        .getSingle();
    expect(chat.data['c'], 2);

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('两个布尔列的 dflt_value = 1（漏默认值会让老库升级直接抛）', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v24_defaults');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV23UserSettings(legacy);
    legacy.execute('''
      CREATE TABLE ai_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 老行先存在：ADD COLUMN NOT NULL 时没有默认值就会立刻抛
    legacy.execute('INSERT INTO user_settings (id) VALUES (1)');
    legacy.execute('PRAGMA user_version = 23');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    final defaults = await _columnDefaults(db, 'user_settings');
    expect(defaults['coach_memory_enabled'], '1',
        reason: 'ALTER TABLE ADD COLUMN 加 NOT NULL 列必须有默认值，这里是唯一必崩点');
    expect(defaults['coach_proactive_enabled'], '1');

    // chips 允许 NULL → 不需要默认值，也**不许**给空串 ''
    expect((await _columnDefaults(db, 'ai_chat_messages'))['chips'], isNull);

    // 老行读到的就是 true
    final row = await db
        .customSelect('SELECT coach_memory_enabled, coach_proactive_enabled '
            'FROM user_settings WHERE id = 1')
        .getSingle();
    expect(row.data['coach_memory_enabled'], 1);
    expect(row.data['coach_proactive_enabled'], 1);

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('v21 → v24：v22 头像昵称 + v23 分类合并 + v24 全链跑通', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v24_from21');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV23UserSettings(legacy, withV22Columns: false);
    legacy.execute('''
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
    legacy.execute('''
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
    legacy.execute('''
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
    legacy.execute('''
      CREATE TABLE ai_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    legacy.execute(
        "INSERT INTO exercises (id, name, category) VALUES (1, '深蹲', 'bodyweight'), (2, '跳绳', 'cardio')");
    legacy.execute('INSERT INTO workout_templates (id, name, difficulty, focus) '
        "VALUES (1, '燃脂', '中阶', '全身')");
    legacy.execute('INSERT INTO workout_template_items (template_id, exercise_id) '
        'VALUES (1, 2)');
    legacy.execute('PRAGMA user_version = 21');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    expect(await _userVersion(db), kSchemaVersion);
    // v22
    expect(await _columns(db, 'user_settings'), containsAll(['nickname', 'avatar_path']));
    // v23
    expect(await _columns(db, 'workout_templates'), contains('type'));
    final cats = await db
        .customSelect('SELECT DISTINCT category FROM exercises ORDER BY category')
        .get();
    expect(cats.map((r) => r.data['category']).toList(), ['cardio', 'strength'],
        reason: 'v23 的 bodyweight → strength 合并不许被 v24 破坏');
    final tplType = await db
        .customSelect('SELECT type FROM workout_templates WHERE id = 1')
        .getSingle();
    expect(tplType.data['type'], 'cardio');
    // v24
    expect(await _tableNames(db), containsAll([
      'coach_memories',
      'coach_proactive_messages',
    ]));
    expect(await _columns(db, 'ai_chat_messages'), contains('chips'));

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('半迁移重跑：v24 的 DDL 已落盘但 user_version 仍是 23 → 不崩、幂等收敛', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v24_replay');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV23UserSettings(legacy);
    legacy.execute('''
      CREATE TABLE ai_chat_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // 上一次迁移把该做的 DDL 都做了，但 user_version 没推进
    legacy.execute('ALTER TABLE user_settings ADD COLUMN coach_memory_enabled '
        'INTEGER NOT NULL DEFAULT 1');
    legacy.execute('ALTER TABLE user_settings ADD COLUMN coach_proactive_enabled '
        'INTEGER NOT NULL DEFAULT 1');
    legacy.execute('ALTER TABLE ai_chat_messages ADD COLUMN chips TEXT');
    legacy.execute('''
      CREATE TABLE coach_memories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        topic TEXT NOT NULL,
        content TEXT NOT NULL,
        quote TEXT NOT NULL,
        source_message_id INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        last_used_at INTEGER,
        UNIQUE (category, topic)
      )
    ''');
    legacy.execute('''
      CREATE TABLE coach_proactive_messages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        dedupe_key TEXT NOT NULL,
        content TEXT NOT NULL,
        source TEXT NOT NULL,
        week_start INTEGER,
        workout_id INTEGER,
        created_at INTEGER NOT NULL DEFAULT 0,
        seen_at INTEGER,
        UNIQUE (dedupe_key)
      )
    ''');
    legacy.execute('CREATE INDEX IF NOT EXISTS idx_coach_proactive_created_at '
        'ON coach_proactive_messages (created_at)');
    legacy.execute('PRAGMA user_version = 23');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();
    expect(await _userVersion(db), kSchemaVersion,
        reason: '重跑必须能收敛到当前版本，不能启动即死');

    // 收敛后功能可用
    await db.into(db.coachMemories).insert(CoachMemoriesCompanion.insert(
          category: 'injury',
          topic: '右膝',
          content: '右膝半月板有旧伤',
          quote: '我右膝半月板有旧伤',
        ));
    expect((await db.select(db.coachMemories).get()).length, 1);

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}

/// v21/v22/v23 的 user_settings 最小可用结构
///
/// [withV22Columns] 为 false 时模拟 v21（没有 nickname / avatar_path）。
void _createV23UserSettings(raw.Database db, {bool withV22Columns = true}) {
  final v22 = withV22Columns ? ', nickname TEXT, avatar_path TEXT' : '';
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
      ai_health_override_count INTEGER NOT NULL DEFAULT 0$v22
    )
  ''');
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return (row.data.values.first as num).toInt();
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

/// 列名 → dflt_value（SQL 字面量字符串；无默认值为 null）
Future<Map<String, String?>> _columnDefaults(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return {
    for (final r in rows) r.read<String>('name'): r.data['dflt_value'] as String?,
  };
}
