import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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

    // 各表 0 行
    for (final table in DataWipeService.tableNames) {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM "$table"')
          .getSingle();
      expect((row.data['c'] as num).toInt(), 0, reason: '$table 必须被清空');
    }

    // 备份 zip 存在（pre-wipe 前缀，不占 keep=4 额度）
    final backupName = report['backup'] as String;
    expect(backupName, startsWith('pre-wipe-'));
    final backupFile = File(p.join(docs.path, 'backups', backupName));
    expect(backupFile.existsSync(), isTrue);

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

  test('空库也能 wipe（各表 0 行 + 依然有备份）', () async {
    final report = await DataWipeService.wipeAll(db: db, docsDir: docs);
    expect(report['ok'], isTrue);
    final backupName = report['backup'] as String;
    expect(File(p.join(docs.path, 'backups', backupName)).existsSync(), isTrue);
  });
}
