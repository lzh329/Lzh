import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/services/backup_candidate_service.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/core/services/restore_service.dart';

/// 第二轮回归验收：只验"返工有没有真的闭环、有没有引入新问题"。
///
/// 与工程师的测试互补，这里专挑**他会写成绿的写法之外**的角度：
/// 1. 清空后**关库重开**（模拟重启）——同一个句柄里看是绿的，重开才是真的；
/// 2. 事务回滚用 SQLite 触发器注入失败（不改任何生产代码）；
/// 3. 降级态用一个 8KB 垃圾文件冒充当前库，确认"坏库原样留档"；
/// 4. 源码守门本身要能拦住回退（改内存副本让它红一次）。
void main() {
  late Directory root;
  late Directory docs;
  late Directory photos;
  late Directory backups;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fittrack_round2');
    docs = Directory(p.join(root.path, 'docs'));
    photos = Directory(p.join(docs.path, 'photos'));
    backups = Directory(p.join(docs.path, 'backups'));
    await photos.create(recursive: true);
    await backups.create(recursive: true);
  });

  tearDown(() async {
    DatabaseSeal.reset();
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  });

  /// 造一个**真实文件库**（不是 memory）：重开才等于"重启 App"
  Future<AppDatabase> openFileDb() async {
    final db = AppDatabase.withExecutor(
      NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))),
    );
    // 强制跑一次查询，触发 onCreate / 种子
    await db.customSelect('SELECT 1').get();
    return db;
  }

  Future<int> countWhere(
    AppDatabase db,
    String table, {
    String where = '',
  }) async {
    final row = await db
        .customSelect(
            'SELECT COUNT(*) AS c FROM "$table"${where.isEmpty ? '' : ' WHERE $where'}')
        .getSingle();
    return (row.data['c'] as num).toInt();
  }

  // ───────────────────────────────────────────────────────────────
  // 1. 清空后内置字典是否真的还在（重开库 = 模拟重启）
  // ───────────────────────────────────────────────────────────────
  group('清空数据后内置字典仍在（关库重开后再验）', () {
    test('重开库后：内置食物 29 / 内置模板 5 + 明细 19 / 动作 32 都在，用户数据全为 0',
        () async {
      var db = await openFileDb();

      // 内置基线（新库自带）
      final builtInFood = await countWhere(db, 'food_library', where: 'is_custom = 0');
      final builtInTpl = await countWhere(db, 'workout_templates', where: 'is_recommended = 1');
      final builtInItems = await countWhere(db, 'workout_template_exercises');
      final exercises = await countWhere(db, 'exercises');
      expect(builtInFood, 29);
      expect(builtInTpl, 5);
      expect(exercises, 32);

      // 用户数据：自建食物 / 自建模板（带明细）/ 训练 / 体重 / 照片
      final customFood = await db.into(db.foodLibrary).insert(
            FoodLibraryCompanion.insert(
              name: 'QA 自建食物',
              caloriesPer100g: 123,
              category: 'other',
              isCustom: const Value(true),
            ),
          );
      final customTpl = await db.into(db.workoutTemplates).insert(
            WorkoutTemplatesCompanion.insert(
              name: 'QA 自建模板',
              difficulty: '入门',
              focus: '全身',
            ),
          );
      await db.into(db.workoutTemplateExercises).insert(
            WorkoutTemplateExercisesCompanion.insert(
              templateId: customTpl,
              exerciseId: (await db.select(db.exercises).get()).first.id,
            ),
          );
      await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));
      await db.into(db.foodLog).insert(FoodLogCompanion.insert(
            date: DateTime(2025, 3, 4, 12),
            foodId: customFood,
            grams: 100,
            mealType: 'lunch',
          ));
      await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);

      final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

      // ── 关库重开：这一步才是"用户重启 App 之后看到的样子" ──
      await db.close();
      db = AppDatabase.withExecutor(
        NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))),
      );
      await db.customSelect('SELECT 1').get();

      expect(await countWhere(db, 'food_library', where: 'is_custom = 0'), builtInFood,
          reason: '内置食物必须一条不少（重开后也不会补种出第二份）');
      expect(await countWhere(db, 'food_library', where: 'is_custom = 1'), 0,
          reason: '用户自建食物必须被清掉');
      expect(await countWhere(db, 'workout_templates', where: 'is_recommended = 1'),
          builtInTpl,
          reason: '内置模板必须还是 5 个，且不许变多');
      expect(await countWhere(db, 'workout_templates', where: 'is_recommended = 0'), 0,
          reason: '用户自建模板必须被清掉');
      expect(await countWhere(db, 'workout_template_exercises'), builtInItems,
          reason: '内置模板的动作明细要保留（$builtInItems 条），自建模板的 1 条要删掉');
      expect(await countWhere(db, 'exercises'), exercises,
          reason: '动作字典本来就不在清理范围里');

      for (final t in ['body_metrics', 'food_log', 'workouts', 'water_log', 'goals']) {
        expect(await countWhere(db, t), 0, reason: '$t 必须清空');
      }
      expect(photos.listSync().whereType<File>(), isEmpty);

      await db.close();
      // 报告口径：只数被删掉的行，不能把保留下来的内置行算进去
      final deleted = report['deleted'] as Map<String, int>;
      expect(deleted['food_library'], 1, reason: '只能算自建的 1 条');
      expect(deleted['workout_templates'], 1);
      expect(deleted['workout_template_exercises'], 1);
      expect(deleted['body_metrics'], 1);
      expect(deleted['food_log'], 1);
    });

    test('连续两次清空：第二次 deleted 合计为 0，内置字典数量不变', () async {
      final db = await openFileDb();
      await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));

      final first = await DataWipeService.wipeAll(db: db, docsDir: docs);
      final second = await DataWipeService.wipeAll(db: db, docsDir: docs);

      expect(
        (first['deleted'] as Map<String, int>)
            .values
            .fold<int>(0, (a, b) => a + b),
        1,
      );
      expect(
        (second['deleted'] as Map<String, int>)
            .values
            .fold<int>(0, (a, b) => a + b),
        0,
        reason: '第二次已经没有用户数据可删',
      );
      expect(await countWhere(db, 'food_library', where: 'is_custom = 0'), 29);
      expect(await countWhere(db, 'workout_templates'), 5,
          reason: '补种必须幂等，不能每清一次多 5 个');
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────
  // 2. 事务回滚：用 SQLite 触发器注入"删到一半失败"
  // ───────────────────────────────────────────────────────────────
  group('清空是一个事务：中途失败必须整段回滚', () {
    const trigger = '''
      CREATE TRIGGER qa_block_water_delete BEFORE DELETE ON water_log
      BEGIN SELECT RAISE(ABORT, 'QA injected failure'); END;
    ''';

    /// 对照组：**不包事务**地按同样顺序删一遍。
    ///
    /// 存在的意义是证明这个注入真的会"删到一半"—— 否则主用例的回滚断言
    /// 可能只是因为异常发生在删除开始之前，那样它会永远是绿的（假通过）。
    test('对照组（无事务）确实会删到一半 —— 证明注入点有效', () async {
      final db = await openFileDb();
      await db.customStatement(trigger);
      await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));
      await db.into(db.waterLog).insert(
          WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 3));

      Object? error;
      for (final table in DataWipeService.tableNames) {
        try {
          await db.customStatement(
              'DELETE FROM "$table"${DataWipeService.deleteScopeOf(table)}');
        } catch (e) {
          error = e;
          break;
        }
      }

      expect('$error', contains('QA injected failure'),
          reason: '异常必须来自注入的触发器，而不是别的什么');
      expect(await countWhere(db, 'body_metrics'), 0,
          reason: '没有事务时，body_metrics 已经被删掉了（这就是"删到一半"）');
      expect(await countWhere(db, 'water_log'), 1);
      await db.close();
    });

    test('wipeAll 里同样的注入 → 整段回滚，一条都没少', () async {
      final db = await openFileDb();

      // water_log 在 tableNames 里排在很后面：等它失败时，前面 10 张表
      // 已经删过一轮了。没有事务的话，这里必然留下"一半清了一半没清"的库。
      await db.customStatement(trigger);

      await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));
      await db.into(db.waterLog).insert(
          WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 3));
      await db.into(db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(role: 'user', content: '你好'));
      final before = {
        'body_metrics': await countWhere(db, 'body_metrics'),
        'ai_chat_messages': await countWhere(db, 'ai_chat_messages'),
        'food_library': await countWhere(db, 'food_library'),
        'workout_template_exercises':
            await countWhere(db, 'workout_template_exercises'),
        'exercises': await countWhere(db, 'exercises'),
      };

      Object? error;
      try {
        await DataWipeService.wipeAll(db: db, docsDir: docs);
      } catch (e) {
        error = e;
      }
      expect('$error', contains('QA injected failure'),
          reason: '必须把失败抛给调用方（不能静默），且是注入的那个失败');

      for (final entry in before.entries) {
        expect(await countWhere(db, entry.key), entry.value,
            reason: '${entry.key} 必须回滚到清空前（事务没生效就会是 0）');
      }
      // 顺便确认注入的失败没有把连接搞坏
      await db.customStatement('DROP TRIGGER qa_block_water_delete');
      final retry = await DataWipeService.wipeAll(db: db, docsDir: docs);
      expect(retry['ok'], isTrue);
      expect(await countWhere(db, 'water_log'), 0);
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────
  // 3. is_recommended 的老库风险（team-lead 点名要结论）
  // ───────────────────────────────────────────────────────────────
  group('is_recommended 判定', () {
    test('新库/迁移库的内置模板一律 is_recommended = 1（否则清空会当成用户模板删掉）',
        () async {
      final db = await openFileDb();
      final templates = await db.select(db.workoutTemplates).get();
      expect(templates, hasLength(5));
      expect(templates.every((t) => t.isRecommended), isTrue,
          reason: 'v12 起种子就一直置 true；全是 0 的库只可能来自人为篡改');
      await db.close();
    });

    test('最坏情况（整列被写成 0）也不会删空：内置模板会被补回 5 个，只是 id 变了',
        () async {
      final db = await openFileDb();
      final idsBefore =
          (await db.select(db.workoutTemplates).get()).map((t) => t.id).toList();
      final namesBefore =
          (await db.select(db.workoutTemplates).get()).map((t) => t.name).toList()
            ..sort();

      // 模拟"旧库这一列全是 0"
      await db.customStatement('UPDATE workout_templates SET is_recommended = 0');

      final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

      final after = await db.select(db.workoutTemplates).get();
      expect(after, hasLength(5), reason: '数量必须回到 5，不能变成 0');
      expect(namesBefore, after.map((t) => t.name).toList()..sort(),
          reason: '内容与清空前一致');
      expect(after.every((t) => t.isRecommended), isTrue,
          reason: '补回来的那份要带 is_recommended = 1，否则下次清空又会被误删');
      expect(after.map((t) => t.id).toList(), isNot(idsBefore),
          reason: '已知代价：id 会变（内置模板的 id 不该被外部持有）');
      // 补种后明细也得跟着回来，否则"快速开始"点进去是空模板
      final items = await db.select(db.workoutTemplateExercises).get();
      expect(items, isNotEmpty, reason: '补种必须把动作明细一起补上');
      expect(
        (report['deleted'] as Map<String, int>)['workout_templates'],
        5,
        reason: '报告要如实说删了 5 个（它当时确实被当成用户模板）',
      );
      await db.close();
    });
  });

  // ───────────────────────────────────────────────────────────────
  // 4. AI 入口口径：预览说删多少，执行就删多少
  // ───────────────────────────────────────────────────────────────
  group('AI 清空入口与设置页口径一致', () {
    test('预览用的删除范围 == 实际删除行数（不许"说删 31 条实际删 2 条"）', () async {
      final db = await openFileDb();
      final customFood = await db.into(db.foodLibrary).insert(
            FoodLibraryCompanion.insert(
              name: 'QA 自建食物',
              caloriesPer100g: 100,
              category: 'other',
              isCustom: const Value(true),
            ),
          );
      final customTpl = await db.into(db.workoutTemplates).insert(
            WorkoutTemplatesCompanion.insert(
              name: 'QA 自建模板',
              difficulty: '入门',
              focus: '全身',
            ),
          );
      await db.into(db.workoutTemplateExercises).insert(
            WorkoutTemplateExercisesCompanion.insert(
              templateId: customTpl,
              exerciseId: (await db.select(db.exercises).get()).first.id,
            ),
          );
      await db.into(db.foodLog).insert(FoodLogCompanion.insert(
            date: DateTime(2025, 3, 4, 12),
            foodId: customFood,
            grams: 100,
            mealType: 'lunch',
          ));
      await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));

      // 复刻 AiToolWipeWriter.preview 的算法（同一份 deleteScopeOf 常量）
      final previewCounts = <String, int>{};
      for (final table in DataWipeService.tableNames) {
        previewCounts[table] = await countWhere(
          db,
          table,
          where: DataWipeService.deleteScopeOf(table).replaceFirst(' WHERE ', ''),
        );
      }

      final report = await DataWipeService.wipeAll(db: db, docsDir: docs);
      final deleted = report['deleted'] as Map<String, int>;

      for (final table in DataWipeService.tableNames) {
        expect(deleted[table], previewCounts[table],
            reason: '$table：预览与实删必须一致');
      }
      expect((deleted['food_library'] ?? 0), 1, reason: '内置 29 条不该被算进删除数');
      expect((deleted['workout_templates'] ?? 0), 1);
      await db.close();
    });

    test('AI 写入器确实复用同一份范围常量与同一个清空实现（源码守门）', () {
      final source =
          File('lib/features/ai/data/ai_tool_wipe_writer.dart').readAsStringSync();
      expect(source, contains('DataWipeService.deleteScopeOf(table)'),
          reason: '预览必须用服务层同一份删除范围，否则口径会分叉');
      expect(source, contains('DataWipeService.wipeAll'),
          reason: '执行必须走同一个清空实现');
    });
  });

  // ───────────────────────────────────────────────────────────────
  // 5. 降级态：用 8KB 垃圾冒充当前库，跑一次真实恢复
  // ───────────────────────────────────────────────────────────────
  group('降级态恢复（当前库是坏的）', () {
    test('8KB 垃圾当前库：坏库被原样留档、新库可打开、进入封存', () async {
      final dbFile = File(p.join(docs.path, 'fittrack.sqlite'));
      final garbage = List<int>.generate(8192, (i) => (i * 37) % 256);
      await dbFile.writeAsBytes(garbage);

      // 用户手上一份好的导出文件
      final good = File(p.join(docs.path, 'fittrack_backup_20251031_235600.sqlite'));
      final goodDb = AppDatabase.withExecutor(NativeDatabase(good));
      await goodDb.customSelect('SELECT 1').get();
      for (var i = 0; i < 4; i++) {
        await goodDb.into(goodDb.bodyMetrics).insert(
            BodyMetricsCompanion.insert(
                date: DateTime(2025, 3, 1 + i), weightKg: 60.0 + i));
      }
      await goodDb.close();
      final goodBytes = await good.readAsBytes();

      final result = await RestoreService.restoreDatabaseFile(
        sourcePath: good.path,
        dbPath: dbFile.path,
        photosDir: photos,
        backupDir: backups,
        docsDir: docs,
        closeDatabase: null, // 降级态：本来就没有可用连接
      );

      // 1) 坏库必须被**原样**留档（一个字节都不能改），否则现场就毁了
      final kept = File(result.preRestorePath);
      expect(await kept.exists(), isTrue);
      expect(await kept.readAsBytes(), garbage,
          reason: '坏库要原样留档给排查，不能被"备份时打开一下"改掉');
      // 2) 新库可用
      final reopened = AppDatabase.withExecutor(
        NativeDatabase(dbFile, enableMigrations: false),
      );
      final rows = await reopened.select(reopened.bodyMetrics).get();
      await reopened.close();
      expect(rows, hasLength(4));
      // 3) 封存 + 备份包
      expect(DatabaseSeal.sealed, isTrue, reason: '必须封存，逼用户重启');
      expect(File(result.preRestoreArchivePath).existsSync(), isTrue);
      // 4) 候选原件没被改
      expect(await good.readAsBytes(), goodBytes);
    });
  });

  // ───────────────────────────────────────────────────────────────
  // 6. 降级态的确认弹窗少了哪一道保护（记录现状 + 待产品决策）
  // ───────────────────────────────────────────────────────────────
  group('降级态的确认口径', () {
    BackupCandidate candidateWith(BackupCounts counts) => BackupCandidate(
          path: '/tmp/fittrack_backup_20251031_235600.sqlite',
          kind: BackupSourceKind.export,
          modifiedAt: DateTime(2025, 10, 31, 23, 56),
          sizeBytes: 138000,
          counts: counts,
          userVersion: kSchemaVersion,
          readable: true,
        );

    // 已修：`RestorePreview.of` 的 destructive 现在把「候选自身就是空库」
    // 独立判成高风险（`candidate.readable && counts.isEmpty`），不再依赖
    // `current != null` —— 降级态读不出当前行数，但那正是用户最急的现场。
    test('降级态（current = null）选空库候选：必须给红色硬警告', () {
      final preview = RestorePreview.of(
        candidate: candidateWith(BackupCounts.zero),
        current: null,
      );

      expect(preview.destructive, isTrue,
          reason: '用空库覆盖在任何情况下都等于清空，与能否对比当前行数无关');
      expect(preview.hardWarning, isNotNull);

      // 摘要里照样把 0 摆出来，让用户自己核对
      expect(preview.summary, contains('体重 0 条'));
      expect(preview.summary, contains('训练 0 次'));
      expect(preview.summary, contains('照片 0 张'));
      expect(preview.notes.join(), contains('读不出行数'));
    });

    test('非降级态选空库候选：仍然必须红（这道保护不能被改坏）', () {
      final preview = RestorePreview.of(
        candidate: candidateWith(BackupCounts.zero),
        current: const BackupCounts(workouts: 1, bodyMetrics: 1),
      );
      expect(preview.destructive, isTrue);
      expect(preview.hardWarning, isNotNull);
    });
  });
}
