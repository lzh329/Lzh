import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/database_health.dart';

/// 用真实（临时文件 / 内存）sqlite 验证「迁移可重入」：
///
/// drift 的 onUpgrade 不在事务里，一旦某个迁移块只跑了一半（DDL 已生效但
/// user_version 未推进），下次启动会从同一个 from 重跑整个块。改造前裸
/// createTable / addColumn 会撞 "table already exists" / "duplicate column
/// name" 抛异常 —— App 启动即死、只能卸载重装（数据全丢）。
void main() {
  test('迁移块可重入：在已建好的 v20 库上重跑所有 onUpgrade 分支不抛异常', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    try {
      // 首次访问触发 onCreate：建全表 + 灌种子
      await db.customSelect('SELECT 1').get();
      expect(db.schemaVersion, kSchemaVersion);

      final templatesBefore = await db.select(db.workoutTemplates).get();
      final foodsBefore = await db.select(db.foodLibrary).get();
      expect(templatesBefore, isNotEmpty);
      expect(foodsBefore, isNotEmpty);

      // 重跑所有历史迁移分支（模拟半迁移后的再次启动）
      for (var from = 1; from < kSchemaVersion; from++) {
        await db.migration.onUpgrade(Migrator(db), from, kSchemaVersion);
      }

      // 没有抛异常 → 可重入；再确认种子没有被重复灌入
      final templatesAfter = await db.select(db.workoutTemplates).get();
      final foodsAfter = await db.select(db.foodLibrary).get();
      expect(templatesAfter.length, templatesBefore.length,
          reason: 'v12 重跑不应重复插入训练模板');
      expect(foodsAfter.length, foodsBefore.length, reason: 'v4 重跑不应重复插入食物库种子');

      // 新表 / 新列都在，说明重跑确实覆盖到了 v20 分支
      final columns =
          await db.customSelect('PRAGMA table_info("user_settings")').get();
      final columnNames = columns.map((row) => row.read<String>('name'));
      expect(columnNames, contains('ai_api_key'));
      expect(columnNames, contains('ai_persona_custom'));
      expect(columnNames, contains('ai_web_search_enabled'));

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((row) => row.read<String>('name'));
      expect(tableNames, contains('ai_chat_messages'));
      expect(tableNames, contains('workout_templates'));
      expect(tableNames, contains('workout_template_exercises'));
    } finally {
      await db.close();
    }
  });

  test('半迁移现场：表已全部存在但 user_version 落后时能继续迁移而不是崩溃', () async {
    final dir = await Directory.systemTemp.createTemp('fittrack_migration');
    final file = File(p.join(dir.path, 'half_migrated.sqlite'));
    var db = AppDatabase.withExecutor(NativeDatabase(file));
    late int templatesBefore;
    try {
      // 第 1 阶段：建一个完整的 v20 库
      await db.customSelect('SELECT 1').get();
      templatesBefore = (await db.select(db.workoutTemplates).get()).length;
      expect(templatesBefore, greaterThan(0));

      // 人为把 user_version 退回 11 —— 等价于「v12 及之后的迁移跑了 DDL
      // 但 user_version 没推进」的半迁移现场
      await db.customStatement('PRAGMA user_version = 11');
      await db.close();

      // 第 2 阶段：同一个文件重新打开 → drift 会重跑 v11..v20 的迁移块，
      // 此时所有表 / 列都已存在。裸 createTable/addColumn 会在这里崩。
      db = AppDatabase.withExecutor(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();

      final templatesAfter = await db.select(db.workoutTemplates).get();
      expect(templatesAfter.length, templatesBefore, reason: '重跑迁移不应重复插入训练模板');

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final tableNames = tables.map((row) => row.read<String>('name')).toList();
      expect(
        tableNames.where((name) => name == 'ai_chat_messages').length,
        1,
        reason: '已存在的表应被跳过，不能被重复创建',
      );
      expect(tableNames, contains('workout_template_exercises'));

      final columns =
          await db.customSelect('PRAGMA table_info("user_settings")').get();
      final columnNames = columns.map((row) => row.read<String>('name'));
      expect(columnNames, contains('ai_api_key'));
      expect(columnNames, contains('ai_web_search_enabled'));
    } finally {
      await db.close();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
  });

  // ── 用例 B（PM/lead 指定）：DDL 中途失败 → user_version 不推进 → 重开自愈 ──
  //
  // 这是「半迁移」的真实成因：迁移块里前几条语句成功、后一条失败，
  // user_version 停在旧值。改造前重跑会在已完成的语句上抛
  // "duplicate column name" 直接死掉；改造后靠幂等助手跳过已完成部分并收敛。
  //
  // 故障注入方式：用一个 BEFORE INSERT 触发器让 v12 的种子写入必然失败
  // （等价于迁移途中遇到磁盘满 / 约束冲突），不需要为此改动生产代码。
  test('用例 B：v12 种子写入失败 → user_version 不推进 → 故障移除后重开自愈', () async {
    final dir = await Directory.systemTemp.createTemp('fittrack_use_case_b');
    final file = File(p.join(dir.path, 'half_failed.sqlite'));
    try {
      // 1) 先造一个完整的 v20 库
      var db = AppDatabase.withExecutor(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      final templatesBefore =
          (await db.select(db.workoutTemplates).get()).length;
      expect(templatesBefore, greaterThan(0));

      // 2) 人为制造「v12 迁移块跑到一半失败」的现场：
      //    user_version 退回 11 + 模板行清空（等价于种子还没写进去）
      //    + 一个必失败的触发器（等价于迁移途中 INSERT 失败）
      await db.customStatement('PRAGMA user_version = 11');
      await db.customStatement('DELETE FROM workout_templates');
      await db.customStatement(
        'CREATE TRIGGER fail_seed BEFORE INSERT ON workout_templates '
        "BEGIN SELECT RAISE(ABORT, 'simulated disk full'); END",
      );
      await db.close();

      // 3) 重开 → 迁移在 v12 块的种子写入处抛异常
      db = AppDatabase.withExecutor(NativeDatabase(file));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(anything),
        reason: '种子写入失败会让整个迁移块中断，这正是半迁移现场',
      );
      try {
        await db.close();
      } catch (_) {
        // 打开失败后 close 可能自己抛，吞掉
      }

      // 4) 关键断言：user_version 没有被推进（读文件头，不打开库）
      expect(
        await DatabaseFileHealth.readUserVersion(file),
        11,
        reason: '迁移失败时 user_version 必须停在旧值，否则下次不会再重试',
      );

      // 5) 移除故障后重开 → 迁移收敛、不抛、种子不重复
      db = AppDatabase.withExecutor(NativeDatabase(
        file,
        setup: (raw) => raw.execute('DROP TRIGGER IF EXISTS fail_seed'),
      ));
      await db.customSelect('SELECT 1').get();

      expect(await DatabaseFileHealth.readUserVersion(file), kSchemaVersion);
      expect(
        (await db.select(db.workoutTemplates).get()).length,
        templatesBefore,
        reason: '重跑后模板数量必须与原库一致（不重复、不丢失）',
      );
      final exercises = await db.select(db.workoutTemplateExercises).get();
      expect(exercises, isNotEmpty, reason: '模板动作明细也应补齐');
      await db.close();
    } finally {
      // Windows 上打开失败后文件句柄可能仍被占用，清理失败不能算测试失败
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
