import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:fittrack/core/database/database.dart';

/// v22 → v23：模板加 type 列 + 动作分类合并（bodyweight/gym → strength）
///
/// 用原生 sqlite3 造 v22 老库（drift 一打开就 onCreate，造不出旧库）。
void main() {
  test('kSchemaVersion 已推进到 23', () {
    expect(kSchemaVersion, 23);
  });

  test('老库 v22 → v23：动作只剩三类、含 cardio 的模板变 cardio、纯力量仍 strength、行数不变', () async {
    final tmp = await Directory.systemTemp.createTemp('fittrack_v23');
    final dbFile = p.join(tmp.path, 'fittrack.sqlite');
    final legacy = raw.sqlite3.open(dbFile);

    // ── 造 v22 的最小可用结构 ──
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

    // 四类动作各一条
    legacy.execute('INSERT INTO exercises (id, name, category) VALUES '
        "(1, '深蹲', 'bodyweight'), (2, '卧推', 'gym'), "
        "(3, '跳绳', 'cardio'), (4, '肩背拉伸', 'stretch')");
    // 模板 A：含 cardio 动作；模板 B：纯力量
    legacy
        .execute('INSERT INTO workout_templates (id, name, difficulty, focus) '
            "VALUES (1, '燃脂', '中阶', '全身'), (2, '力量', '入门', '全身')");
    legacy.execute(
        'INSERT INTO workout_template_items (template_id, exercise_id) '
        'VALUES (1, 3), (1, 1), (2, 1), (2, 2)');

    legacy.execute('PRAGMA user_version = 22');
    legacy.dispose();

    // ── 用当前 schema 打开 → 触发 v22→v23 ──
    final db = AppDatabase.withExecutor(NativeDatabase(File(dbFile)));
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 23);

    // 动作只剩三类
    final cats = await db
        .customSelect(
            'SELECT DISTINCT category FROM exercises ORDER BY category')
        .get();
    expect(cats.map((r) => r.data['category']).toList(),
        ['cardio', 'strength', 'stretch']);

    // bodyweight / gym 都并成 strength
    final strength = await db
        .customSelect(
            "SELECT COUNT(*) AS c FROM exercises WHERE category = 'strength'")
        .getSingle();
    expect(strength.data['c'], 2);

    // 模板类型
    final t1 = await db
        .customSelect('SELECT type FROM workout_templates WHERE id = 1')
        .getSingle();
    final t2 = await db
        .customSelect('SELECT type FROM workout_templates WHERE id = 2')
        .getSingle();
    expect(t1.data['type'], 'cardio', reason: '含 cardio 动作 → 自动归为有氧');
    expect(t2.data['type'], 'strength', reason: '纯力量模板保持力量');

    // 老数据行数不变
    final exCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM exercises')
        .getSingle();
    final tplCount = await db
        .customSelect('SELECT COUNT(*) AS c FROM workout_templates')
        .getSingle();
    expect(exCount.data['c'], 4);
    expect(tplCount.data['c'], 2);

    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });
}
