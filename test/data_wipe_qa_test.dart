import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';

/// 「清除所有数据」的服务层验收。
///
/// 和工程师的测试互补，重点补三处最容易漏的：
/// 1. 备份失败时的**零删除**（换一种失败方式：备份目录不可写）；
/// 2. 清空**不能顺手删掉备份**（否则"先备份"就是自欺欺人）；
/// 3. 备份包 manifest 里要带 `weekly_report_cache` 行数，
///    这样"清完又想找回周报"仍然有据可查。
void main() {
  late AppDatabase db;
  late Directory docs;
  late Directory photos;
  late Directory backups;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    docs = await Directory.systemTemp.createTemp('fittrack_wipe_qa');
    photos = Directory(p.join(docs.path, 'photos'));
    backups = Directory(p.join(docs.path, 'backups'));
    await photos.create(recursive: true);
    await backups.create(recursive: true);
    // wipeAll 会先把 docs/fittrack.sqlite 打成包，所以磁盘上要有真实库文件
    final fileDb = AppDatabase.withExecutor(
      NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))),
    );
    await fileDb.customSelect('SELECT 1').get();
    await fileDb.close();
  });

  tearDown(() async {
    await db.close();
    try {
      if (await docs.exists()) await docs.delete(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> manifestOf(File zipFile) {
    final archive = ZipDecoder().decodeBytes(zipFile.readAsBytesSync());
    final entry = archive.files.firstWhere((f) => f.name == 'manifest.json');
    return jsonDecode(utf8.decode(entry.content as List<int>))
        as Map<String, dynamic>;
  }

  test('备份目录不可写 → 一条记录都不删（换一种失败方式重测同一约束）', () async {
    await db.into(db.bodyMetrics).insert(
        BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 3));
    await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1, 2, 3]);

    // 把 backups 变成一个**文件**：建目录这一步必然失败
    await backups.delete(recursive: true);
    await File(backups.path).writeAsBytes([0]);

    await expectLater(
      DataWipeService.wipeAll(db: db, docsDir: docs),
      throwsA(anything),
    );

    expect((await db.select(db.bodyMetrics).get()).length, 1,
        reason: '备份失败就必须一条都不删');
    expect((await db.select(db.waterLog).get()).length, 1);
    expect(File(p.join(photos.path, 'a.jpg')).existsSync(), isTrue,
        reason: '备份失败时照片也不许删');
  });

  test('清空数据不会删掉之前存下的备份文件（否则先备份等于没备）', () async {
    final oldBackup = File(p.join(backups.path, 'fittrack_backup_old.zip'));
    await oldBackup.writeAsBytes([9, 9, 9]);
    final oldSqlite =
        File(p.join(backups.path, 'pre-restore-20250101-000000.sqlite'));
    await oldSqlite.writeAsBytes([8, 8, 8]);
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 2));

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect(oldBackup.existsSync(), isTrue, reason: '历史备份包必须留着');
    expect(oldSqlite.existsSync(), isTrue, reason: 'pre-restore 副本必须留着');
  });

  test('备份包 manifest 里带 weekly_report_cache 行数（清完仍可核对/找回）', () async {
    await db.into(db.weeklyReportCache).insert(
          WeeklyReportCacheCompanion.insert(
            weekStart: DateTime(2025, 3, 3),
            content: '本周体重下降 0.5kg',
          ),
        );
    await db.into(db.bodyMetrics).insert(
        BodyMetricsCompanion.insert(date: DateTime(2025, 3, 4), weightKg: 70));

    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

    final backupName = report['backup'] as String;
    final manifest = manifestOf(File(p.join(backups.path, backupName)));
    final counts = manifest['tableCounts'] as Map<String, dynamic>;
    expect(counts['weekly_report_cache'], 1,
        reason: '周报缓存也必须进备份，否则清完就真没了');
    expect(counts['body_metrics'], 1);
    expect(manifest['photoCount'], 0);
  });

  test('photos 目录里的非图片杂项文件也会被清（不留孤儿）', () async {
    await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1]);
    await File(p.join(photos.path, 'b.png')).writeAsBytes([2]);
    await File(p.join(photos.path, '.nomedia')).writeAsBytes([0]);

    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect(report['photos_deleted'], 3);
    expect(photos.listSync().whereType<File>(), isEmpty);
  });

  test('重复清空是幂等的：第二次各表都是 0 条，且仍然会打一份备份', () async {
    await db.into(db.waterLog).insert(
        WaterLogCompanion.insert(date: DateTime(2025, 3, 4, 9), cups: 2));

    await DataWipeService.wipeAll(db: db, docsDir: docs);
    final second = await DataWipeService.wipeAll(db: db, docsDir: docs);

    final deleted = second['deleted'] as Map<String, int>;
    expect(deleted.values.fold<int>(0, (a, b) => a + b), 0);
    expect(
      File(p.join(backups.path, second['backup'] as String)).existsSync(),
      isTrue,
    );
  });

  // ── 缺陷占位（先 skip 保住门禁，修好后去掉 skip 即为回归门禁）──
  //
  // 实测（见交付回执「问题 #1」）：_seedFoodLibrary / _seedWorkoutTemplates
  // 只在 onCreate 与 v4 迁移块里跑，user_version 已经是 23 之后**不会再灌**。
  // 于是 wipe 之后：内置食物 29 → 0、内置模板 5 → 0，而内置动作 32 条还在
  // （exercises 不在 tableNames 里）。也就是说清完反而回不到"初始可用状态"：
  // 饮食页选不到"白米饭"，快速开始页没有模板。
  test('清除数据后内置食物库仍然可用（清的是用户数据，不是内置字典）', () async {
    final before = await db.select(db.foodLibrary).get();
    expect(before, isNotEmpty, reason: '新建库自带内置食物');

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    final after = await db.select(db.foodLibrary).get();
    expect(after.where((f) => !f.isCustom), isNotEmpty,
        reason: '内置食物（isCustom=false）必须保留或重新灌入');
    expect(after.where((f) => f.isCustom), isEmpty,
        reason: '用户自己加的食物才该被清掉');
  });

  test('清除数据后内置训练模板仍然可用', () async {
    expect(await db.select(db.workoutTemplates).get(), isNotEmpty,
        reason: '新建库自带 5 个内置模板');

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect(await db.select(db.workoutTemplates).get(), isNotEmpty,
        reason: '清空后回到"刚装好"的状态，模板不该一起消失');
  });
}
