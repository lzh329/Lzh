import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/migration_failure_marker.dart';

/// QA 补充：迁移**成功之后必须清掉失败标记**（`MigrationFailureMarker` 的契约）。
///
/// 为什么值得单写一条：这个标记决定启动时进「数据库失败页」还是正常启动。
/// 迁移失败一次会写标记；用户再开一次、这次迁移成功了，标记必须被删掉，
/// 否则下一次冷启动会拿旧标记去判"迁移没完成"。
/// bootstrap 里虽然有"僵尸标记自愈"（user_version == schemaVersion 就清），
/// 但那是**第二道**防线，且依赖 `user_version` 探测成功 —— 探测读不出文件头时
/// 会直接判定 `unreadable` 进降级页。第一道防线（迁移成功后清）不能缺。
void main() {
  // ⚠️ 缺陷 D3（已报工程师）：`database.dart:819` 的 clear() 被并进注释行，实际不执行。
  // 修好后去掉 skip 即为回归门禁。实测证据见交付回执。
  test('v24 → v25 迁移成功：上一次留下的 migration_failure.json 必须被删除',
      () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_marker_v25');
    addTearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);
    _createV24UserSettings(legacy);
    legacy.execute('PRAGMA user_version = 24');
    legacy.dispose();

    // 模拟"上一次升级失败过"：标记文件已经躺在文档目录里
    await MigrationFailureMarker.record(
      fromVersion: 24,
      targetVersion: 25,
      failingStep: 'addColumn:character_id',
      baseDir: tmp,
    );
    final markerFile =
        File(p.join(tmp.path, MigrationFailureMarker.fileName));
    expect(markerFile.existsSync(), isTrue, reason: '前置条件：标记文件已在');

    // 这次升级会成功（库是干净的 v24）
    final db = AppDatabase.withExecutor(
      NativeDatabase(File(dbFile)),
      markerBaseDir: tmp,
    );
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = (await db.customSelect('PRAGMA user_version').getSingle())
        .data
        .values
        .first as int;
    expect(version, kSchemaVersion,
        reason: '前置条件：这次迁移确实成功了（断言当前版本，不为每次升版改数字）');

    expect(markerFile.existsSync(), isFalse,
        reason: '迁移成功后必须清掉旧失败标记，否则下次冷启动会误判为"迁移没完成"');
  });
}

/// v24 的 user_settings 最小结构（没有 character_id）
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
