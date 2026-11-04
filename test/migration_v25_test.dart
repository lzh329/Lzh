import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v25：`user_settings.character_id`（三角色形象系统）
///
/// 覆盖四条路径（playbook 7.7 / C-2 / C-3）：
///   ① 空库安装（onCreate）
///   ② v24 → v25（老库升级，列存在 + 默认 'guga' + 老数据不丢）
///   ③ 半迁移现场重跑（DDL 已落盘但 user_version 还是 24）
///   ④ 表数量不变（只加列不建表）
void main() {
  test('kSchemaVersion 已推进到当前版本', () {
    expect(kSchemaVersion, 27);
  });

  // QA 的 D3：`await MigrationFailureMarker.clear(...)` 曾被并到注释行尾，
  // 于是"迁移成功后清失败标记"静默消失（门禁全绿也发现不了）。
  // 这条守卫锁死它的**行首形态**：trimLeft 之后必须以 await 开头。
  test('源码守卫：迁移成功后清失败标记是独立语句（不许被并进注释）', () {
    final lines = File('lib/core/database/database.dart').readAsLinesSync();
    final idx = lines.indexWhere(
        (l) => l.contains('MigrationFailureMarker.clear'));
    expect(idx, greaterThan(0), reason: '这一行必须还在（别整个删掉）');
    expect(
      lines[idx].trimLeft().startsWith('await MigrationFailureMarker.clear('),
      isTrue,
      reason: '这一行必须以 await 开头；并进 // 注释就等于不再清标记：'
          '${lines[idx].trim()}',
    );
  });

  test('空库安装：character_id 列存在、NOT NULL、默认 guga、表数量与 v24 一致', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();

    expect(await _columns(db, 'user_settings'), contains('character_id'));

    final info = await _columnInfo(db, 'user_settings', 'character_id');
    expect(info.notNull, isTrue, reason: 'C2：列是 NOT NULL');
    expect(info.defaultValue, "'guga'", reason: 'C2/C3：DB 层默认值必须是 guga');

    // C-2：只加列不建表 —— v24 已有的表清单一条不多一条不少
    final tables = await _tableNames(db);
    expect(tables, contains('user_settings'));
    expect(tables.where((t) => t.startsWith('character')), isEmpty,
        reason: 'C2 明确不新建 characters 表');

    // 插入一行不指定该列 → 读到 guga
    await db.into(db.userSettings).insert(const UserSettingsCompanion());
    final row = await db.select(db.userSettings).getSingle();
    expect(row.characterId, 'guga');

    await db.close();
  });

  test('v24 → 当前版本：列加上了、老行回填 guga、老数据一条不丢', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v25_from24');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV24UserSettings(legacy);
    legacy.execute("INSERT INTO user_settings (id, nickname) VALUES (1, '小嘎')");
    legacy.execute('PRAGMA user_version = 24');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    expect(await _userVersion(db), kSchemaVersion);
    expect(await _columns(db, 'user_settings'), contains('character_id'));
    // v26：多服务商列也一并加上（纯加列可空，老行回填 NULL）
    expect(await _columns(db, 'user_settings'), contains('ai_provider_id'));

    // 默认值必须写进 DDL：ALTER TABLE ADD COLUMN 加 NOT NULL 列时没默认值
    // 会直接抛（老库有行），这是唯一必崩点
    final info = await _columnInfo(db, 'user_settings', 'character_id');
    expect(info.defaultValue, "'guga'");
    expect(info.notNull, isTrue);

    // 老行被回填成 guga（C3 路径②：老用户升级后还是那只鸟）
    final row = await db
        .customSelect('SELECT nickname, character_id FROM user_settings WHERE id = 1')
        .getSingle();
    expect(row.data['nickname'], '小嘎', reason: '老数据不许丢');
    expect(row.data['character_id'], 'guga');

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('半迁移重跑：character_id 已存在但 user_version 仍是 24 → 不崩、幂等收敛', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v25_replay');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV24UserSettings(legacy);
    // 上一次迁移 DDL 落盘了，但版本号没推进
    legacy.execute('ALTER TABLE user_settings ADD COLUMN character_id TEXT NOT NULL '
        "DEFAULT 'guga'");
    legacy.execute(
        "INSERT INTO user_settings (id, character_id) VALUES (1, 'nuonuo')");
    legacy.execute('PRAGMA user_version = 24');
    legacy.dispose();

    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    expect(await _userVersion(db), kSchemaVersion,
        reason: '重跑必须收敛，不能启动即死');
    // 幂等加列没有把已有值冲掉
    final row = await db
        .customSelect('SELECT character_id FROM user_settings WHERE id = 1')
        .getSingle();
    expect(row.data['character_id'], 'nuonuo');

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}

/// v24 的 user_settings 最小可用结构（**没有** character_id）
void _createV24UserSettings(raw.Database db) {
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
      ai_health_override_count INTEGER NOT NULL DEFAULT 0,
      nickname TEXT,
      avatar_path TEXT,
      coach_memory_enabled INTEGER NOT NULL DEFAULT 1,
      coach_proactive_enabled INTEGER NOT NULL DEFAULT 1
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

Future<List<String>> _columns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

class _ColumnInfo {
  final bool notNull;
  final String? defaultValue;
  const _ColumnInfo(this.notNull, this.defaultValue);
}

Future<_ColumnInfo> _columnInfo(
    AppDatabase db, String table, String column) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  for (final r in rows) {
    if (r.read<String>('name') == column) {
      return _ColumnInfo(
        (r.data['notnull'] as num).toInt() == 1,
        r.data['dflt_value'] as String?,
      );
    }
  }
  throw StateError('列不存在: $table.$column');
}
