import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';

void main() {
  late AppDatabase db;
  late Directory docs;
  late Directory photos;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    docs = await Directory.systemTemp.createTemp('fittrack_wipe');
    photos = Directory(p.join(docs.path, 'photos'));
    await photos.create(recursive: true);
    // wipe 前会先打包 docs/fittrack.sqlite，先造一个真实文件库
    final fileDb =
        AppDatabase.withExecutor(NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))));
    await fileDb.customSelect('SELECT 1').get();
    await fileDb.close();
  });

  tearDown(() async {
    await db.close();
    try {
      if (await docs.exists()) await docs.delete(recursive: true);
    } catch (_) {}
  });

  test('建数据 → wipe → 各表 0 行，备份 zip 存在且含照片', () async {
    // 造数据：体重、饮水、食物、自定义食物、聊天、身体信息
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
          date: DateTime(2025, 3, 4),
          weightKg: 70,
        ));
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 3));
    await db.into(db.aiChatMessages).insert(
          AiChatMessagesCompanion.insert(role: 'user', content: '你好'),
        );
    final foodId = await db.into(db.foodLibrary).insert(
          FoodLibraryCompanion.insert(
            name: '测试食物',
            caloriesPer100g: 100,
            category: 'other',
            // 只有 is_custom 的是"用户自己加的"，内置食物不在清空范围内
            isCustom: const Value(true),
          ),
        );
    await db.into(db.foodLog).insert(FoodLogCompanion.insert(
          date: DateTime(2025, 3, 4, 12),
          foodId: foodId,
          grams: 100,
          mealType: 'lunch',
        ));
    await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);

    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);
    expect(report['ok'], isTrue);

    // 各表的**用户数据** 0 行（内置字典表的删除范围只有用户新增的行）
    for (final table in DataWipeService.tableNames) {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM "$table"'
            '${DataWipeService.deleteScopeOf(table)}',
          )
          .getSingle();
      expect((row.data['c'] as num).toInt(), 0, reason: '$table 的用户数据必须被清空');
    }

    // 内置字典必须还在：删了就再也回不来（种子只在 onCreate/迁移里灌一次）
    expect(
      (await db.select(db.foodLibrary).get()).where((f) => !f.isCustom),
      isNotEmpty,
      reason: '内置食物库要保留，否则清空后饮食页选不到任何食物',
    );
    expect(await db.select(db.workoutTemplates).get(), isNotEmpty,
        reason: '内置训练模板要保留');
    expect(
      (await db.select(db.workoutTemplates).get())
          .where((t) => t.isRecommended),
      hasLength(5),
      reason: '内置模板应当是 5 个，且清空不会让它们变多或变少',
    );

    // 报告里的行数必须是"清空前"的真实值，UI 直接拿它告诉用户清掉了多少
    final deleted = report['deleted'] as Map<String, int>;
    expect(deleted['body_metrics'], 1);
    expect(deleted['water_log'], 1);
    expect(deleted['food_log'], 1);
    expect(deleted['food_library'], 1, reason: '只统计被删掉的自定义食物');
    expect(deleted['ai_chat_messages'], 1);

    // 照片：表清了，磁盘文件也要清（否则残留孤儿文件，用户还会在相册里看到）
    expect(photos.listSync().whereType<File>(), isEmpty,
        reason: 'photos 目录里的图片文件必须一起删掉');

    // 备份 zip 存在（pre-wipe 前缀，不占 keep=4 额度）
    final backupName = report['backup'] as String;
    expect(backupName, startsWith('pre-wipe-'));
    final backupFile = File(p.join(docs.path, 'backups', backupName));
    expect(backupFile.existsSync(), isTrue,
        reason: '先备份再清空：备份包必须真的落盘');

    // 备份里有照片（清空前打的包）
    final bytes = backupFile.readAsBytesSync();
    final manifest = utf8.decode(
      ZipDecoder()
          .decodeBytes(bytes)
          .files
          .firstWhere(
            (f) => f.name == 'manifest.json',
          )
          .content as List<int>,
    );
    expect(manifest, contains('"photoCount": 1'));
    expect(report['photos_deleted'], 1);
  });

  test('schema 不变（DELETE 不 DROP）：wipe 后表结构仍在，还能插入', () async {
    await DataWipeService.wipeAll(db: db, docsDir: docs);
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 2));
    final rows = await db.select(db.waterLog).get();
    expect(rows.single.cups, 2, reason: 'DELETE 不 DROP：迁移状态不受影响');
  });

  test('用户自建模板被清掉，内置模板的动作明细一条不少、也不留孤儿', () async {
    final customId = await db.into(db.workoutTemplates).insert(
          WorkoutTemplatesCompanion.insert(
            name: '我的自定义模板',
            difficulty: '入门',
            focus: '全身',
          ),
        );
    final exercise = (await db.select(db.exercises).get()).first;
    await db.into(db.workoutTemplateExercises).insert(
          WorkoutTemplateExercisesCompanion.insert(
            templateId: customId,
            exerciseId: exercise.id,
            targetSets: const Value(3),
          ),
        );
    final builtInItemsBefore = (await db.select(db.workoutTemplateExercises).get())
        .where((i) => i.templateId != customId)
        .length;

    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect((report['deleted'] as Map<String, int>)['workout_templates'], 1,
        reason: '只删用户自建的那一个');
    final templates = await db.select(db.workoutTemplates).get();
    expect(templates.where((t) => t.isRecommended), hasLength(5),
        reason: '内置 5 个必须还在，且不许变多（幂等）');
    expect(templates.where((t) => !t.isRecommended), isEmpty);

    final items = await db.select(db.workoutTemplateExercises).get();
    expect(items.length, builtInItemsBefore,
        reason: '内置模板的动作明细不能被清掉');
    final templateIds = templates.map((t) => t.id).toSet();
    expect(items.every((i) => templateIds.contains(i.templateId)), isTrue,
        reason: '不许留下指向已删模板的孤儿明细');
  });

  test('连续两次清空不会把内置模板灌成两份', () async {
    await DataWipeService.wipeAll(db: db, docsDir: docs);
    await DataWipeService.wipeAll(db: db, docsDir: docs);

    final templates = await db.select(db.workoutTemplates).get();
    expect(templates.where((t) => t.isRecommended), hasLength(5),
        reason: '补种必须幂等：不能每清一次就多 5 个');
    expect(
      (await db.select(db.foodLibrary).get()).where((f) => !f.isCustom).length,
      29,
      reason: '内置食物也不能重复灌',
    );
  });

  test('空库也能 wipe（各表 0 行 + 依然有备份）', () async {
    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);
    expect(report['ok'], isTrue);
    final backupName = report['backup'] as String;
    expect(File(p.join(docs.path, 'backups', backupName)).existsSync(), isTrue);
  });

  test('周报缓存也一起清（记录删了、AI 旧周报还留着 = 没清干净）', () async {
    await db.into(db.weeklyReportCache).insert(
          WeeklyReportCacheCompanion.insert(
            weekStart: DateTime(2025, 3, 3),
            content: '本周体重下降 0.5kg',
          ),
        );

    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect(
      (report['deleted'] as Map<String, int>)['weekly_report_cache'],
      1,
      reason: '周报是按当时的记录生成的正文，必须跟记录一起清',
    );
    expect(await db.select(db.weeklyReportCache).get(), isEmpty);
  });

  test('备份失败就一条都不删（先备份是硬约束）', () async {
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 3));
    // 把"数据库主文件"删掉，让备份阶段必定失败
    await File(p.join(docs.path, 'fittrack.sqlite')).delete();

    await expectLater(
      DataWipeService.wipeAll(db: db, docsDir: docs),
      throwsA(anything),
    );
    expect((await db.select(db.waterLog).get()).length, 1,
        reason: '没有备份就绝不删数据');
  });
}
