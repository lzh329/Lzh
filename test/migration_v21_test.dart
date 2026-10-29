import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/database_health.dart';
import 'package:fittrack/core/database/migration_failure_marker.dart';

/// v21 迁移验收：两张表 + 一列 + 九条索引，两条路径（新装 / 老库升级）都要对。
Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((r) => r.read<String>('name')).toList();
}

Future<Set<String>> _indexNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
      .get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<List<String>> _columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info("$table")').get();
  return rows.map((r) => r.read<String>('name')).toList();
}

/// 九条索引名（与 `@TableIndex` 注解、`kV21Indexes` 三处必须逐字一致）
const _expectedIndexes = <String>[
  'idx_workouts_date',
  'idx_body_metrics_date',
  'idx_food_log_date',
  'idx_water_log_date',
  'idx_photos_date',
  'idx_ai_chat_messages_created_at',
  'idx_workout_sets_workout_id',
  'idx_plan_days_plan_id',
  'idx_workout_template_exercises_template_id',
];

void main() {
  late Directory dir;
  late File file;
  late Directory markerDir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fittrack_v21');
    file = File(p.join(dir.path, 'v21.sqlite'));
    markerDir = Directory(p.join(dir.path, 'markers'));
    await markerDir.create(recursive: true);
  });

  tearDown(() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Windows 上失败打开后句柄可能仍被占用
    }
  });

  AppDatabase open({NativeDatabase? executor}) => AppDatabase.withExecutor(
        executor ?? NativeDatabase(file),
        markerBaseDir: markerDir,
      );

  group('新装用户（走 onCreate → createAll）', () {
    test('两张新表 + 计数列 + 九条索引全部就位，user_version == 21', () async {
      final db = open();
      await db.customSelect('SELECT 1').get();

      final tables = await _tableNames(db);
      expect(tables, contains('daily_overrides'));
      expect(tables, contains('weekly_report_cache'));

      expect(
        await _columnNames(db, 'user_settings'),
        contains('ai_health_override_count'),
      );

      final indexes = await _indexNames(db);
      expect(indexes, containsAll(_expectedIndexes),
          reason: '@TableIndex 只覆盖新装用户，漏了这条新装库里就没有索引');

      // schema 已到 22：打开即一路升到最新，断言最新版本
expect(await DatabaseFileHealth.readUserVersion(file), kSchemaVersion);
      await db.close();
    });

    test('kV21Indexes 与 @TableIndex 的索引名逐字一致（9 条，不多不少）', () {
      expect(kV21Indexes.length, 9);
      for (final expected in _expectedIndexes) {
        expect(
          kV21Indexes.where((sql) => sql.contains(expected)).length,
          1,
          reason: '迁移侧缺少索引 $expected —— 老库永远建不上它',
        );
      }
    });

    test(
        'daily_overrides.date / weekly_report_cache.week_start 是唯一约束，'
        '且没有额外的同名索引（重复索引只会拖慢写入）', () async {
      final db = open();
      await db.customSelect('SELECT 1').get();

      // 唯一约束会由 SQLite 自动建 sqlite_autoindex_*
      final indexes = await _indexNames(db);
      expect(
          indexes.any((n) => n.startsWith('sqlite_autoindex_daily_overrides')),
          isTrue);
      expect(
        indexes
            .any((n) => n.startsWith('sqlite_autoindex_weekly_report_cache')),
        isTrue,
      );
      expect(indexes.contains('idx_daily_overrides_date'), isFalse);
      expect(indexes.contains('idx_weekly_report_cache_week_start'), isFalse);

      // 一天只能一条：插第二条同日期必须失败
      await db.into(db.dailyOverrides).insert(
            DailyOverridesCompanion.insert(
              date: DateTime(2025, 3, 4),
              source: 'user',
            ),
          );
      await expectLater(
        db.into(db.dailyOverrides).insert(
              DailyOverridesCompanion.insert(
                date: DateTime(2025, 3, 4),
                source: 'ai',
              ),
            ),
        throwsA(anything),
        reason: 'uniqueKeys 必须真的生效（一天一条）',
      );
      await db.close();
    });

    test('macroJudgement 默认 normal、reminderPaused 默认 false', () async {
      final db = open();
      await db.customSelect('SELECT 1').get();
      await db.into(db.dailyOverrides).insert(
            DailyOverridesCompanion.insert(
              date: DateTime(2025, 3, 4),
              source: 'user',
            ),
          );
      final row = await db.select(db.dailyOverrides).getSingle();
      expect(row.macroJudgement, 'normal');
      expect(row.reminderPaused, isFalse);
      await db.close();
    });
  });

  group('老库升级（from = 20 → 21）', () {
    /// 造一个「v20 现场」：删掉 v21 建的两张表 + 两条索引，user_version 退回 20。
    Future<void> degradeToV20(AppDatabase db) async {
      await db.customStatement('DROP TABLE daily_overrides');
      await db.customStatement('DROP TABLE weekly_report_cache');
      await db.customStatement('DROP INDEX IF EXISTS idx_food_log_date');
      await db
          .customStatement('DROP INDEX IF EXISTS idx_workout_sets_workout_id');
      await db.customStatement('PRAGMA user_version = 20');
    }

    test('升级后两张表 / 九条索引全在，旧数据可读，user_version == 21', () async {
      var db = open();
      await db.customSelect('SELECT 1').get();

      // 造一条 v20 时代就有的数据，升级后必须还在
      await db.into(db.bodyMetrics).insert(
            BodyMetricsCompanion.insert(
              date: DateTime(2024, 6, 1),
              weightKg: 72.5,
            ),
          );

      await degradeToV20(db);
      await db.close();

      db = open();
      await db.customSelect('SELECT 1').get();

      final tables = await _tableNames(db);
      expect(tables, contains('daily_overrides'));
      expect(tables, contains('weekly_report_cache'));
      expect(await _indexNames(db), containsAll(_expectedIndexes));

      final metrics = await db.select(db.bodyMetrics).get();
      expect(metrics.length, 1);
      expect(metrics.single.weightKg, 72.5);

      // schema 已到 22：打开即一路升到最新，断言最新版本
expect(await DatabaseFileHealth.readUserVersion(file), kSchemaVersion);
      await db.close();
    });

    test('再开一次不抛、不重复（幂等）', () async {
      var db = open();
      await db.customSelect('SELECT 1').get();
      await degradeToV20(db);
      await db.close();

      for (var i = 0; i < 3; i++) {
        db = open();
        await db.customSelect('SELECT 1').get();
        await db.close();
      }

      db = open();
      await db.customSelect('SELECT 1').get();
      // schema 已到 22：打开即一路升到最新，断言最新版本
expect(await DatabaseFileHealth.readUserVersion(file), kSchemaVersion);
      // 重置版本的迁移块重跑后，索引不会变成两倍
      final indexes = await _indexNames(db);
      expect(
        indexes.where((n) => n.startsWith('idx_')).length,
        _expectedIndexes.length,
      );
      await db.close();
    });

    test('升级成功后 marker 被删除', () async {
      var db = open();
      await db.customSelect('SELECT 1').get();
      await degradeToV20(db);
      await db.close();

      db = open();
      await db.customSelect('SELECT 1').get();
      expect(
        await MigrationFailureMarker.read(baseDir: markerDir),
        isNull,
        reason: '成功迁移必须清掉失败标记，否则降级页会误报',
      );
      await db.close();
    });
  });

  group('失败诊断（步骤级 failingStep）', () {
    test('索引步骤失败 → marker 记录到具体索引名，user_version 不推进', () async {
      var db = open();
      await db.customSelect('SELECT 1').get();
      await db.into(db.bodyMetrics).insert(
            BodyMetricsCompanion.insert(
              date: DateTime(2024, 6, 1),
              weightKg: 70,
            ),
          );

      // 制造 v21 索引步骤必然失败：把 food_log 表删掉，
      // 于是 `CREATE INDEX ... ON food_log (date)` 会报 no such table
      await db.customStatement('DROP TABLE food_log');
      await db.customStatement('DROP TABLE daily_overrides');
      await db.customStatement('DROP TABLE weekly_report_cache');
      await db.customStatement('PRAGMA user_version = 20');
      await db.close();

      db = open();
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(anything),
        reason: 'food_log 不存在时建索引必然失败',
      );
      try {
        await db.close();
      } catch (_) {}

      final marker = await MigrationFailureMarker.read(baseDir: markerDir);
      expect(marker, isNotNull);
      expect(marker!.targetVersion, kSchemaVersion);
      expect(
        marker.failingStep,
        'index:idx_food_log_date',
        reason: 'failingStep 必须精确到具体索引，否则用户截图回来定位不到',
      );
      expect(marker.attemptCount, 1);

      // 版本没推进，下次启动还会重试
      expect(await DatabaseFileHealth.readUserVersion(file), 20);

      // 再开一次：attemptCount 递增（说明是必现而非偶发）
      final again = open();
      await expectLater(
          again.customSelect('SELECT 1').get(), throwsA(anything));
      try {
        await again.close();
      } catch (_) {}
      final second = await MigrationFailureMarker.read(baseDir: markerDir);
      expect(second!.attemptCount, 2);
    });

    test('旧数据在失败后仍可读（纯 DDL 失败不动用户数据）', () async {
      var db = open();
      await db.customSelect('SELECT 1').get();
      await db.into(db.bodyMetrics).insert(
            BodyMetricsCompanion.insert(
              date: DateTime(2024, 6, 1),
              weightKg: 66.6,
            ),
          );
      await db.customStatement('DROP TABLE food_log');
      await db.customStatement('DROP TABLE daily_overrides');
      await db.customStatement('DROP TABLE weekly_report_cache');
      await db.customStatement('PRAGMA user_version = 20');
      await db.close();

      // 打开失败后，用裸连接把故障移除（补回 food_log 表的最小结构）
      final raw = open(
        executor: NativeDatabase(file, setup: (r) {
          r.execute(
            'CREATE TABLE IF NOT EXISTS food_log ('
            'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            'date INTEGER NOT NULL, '
            'food_id INTEGER NOT NULL, '
            'grams REAL NOT NULL, '
            'meal_type TEXT NOT NULL)',
          );
        }),
      );
      await raw.customSelect('SELECT 1').get();
      final metrics = await raw.select(raw.bodyMetrics).get();
      expect(metrics.single.weightKg, 66.6, reason: 'v21 是纯 DDL，失败不该动用户数据一个字节');
      // schema 已到 22：打开即一路升到最新，断言最新版本
expect(await DatabaseFileHealth.readUserVersion(file), kSchemaVersion);
      await raw.close();
    });
  });
}
