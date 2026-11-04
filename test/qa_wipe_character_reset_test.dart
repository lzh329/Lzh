import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

/// QA 补充：C-3 的第三条路径 —— **清空数据后回到咕嘎**。
///
/// 规范把「wipe 后默认 guga」写成验收项（C-3），但全库没有任何测试覆盖
/// `user_settings` 里 v25 这一列。这里同时验证三件事：
///   ① 选过菲比 → 清空后读到的是咕嘎（不是残留的 phoebe，也不是 null 崩溃）；
///   ② 内置食物 / 内置模板还在（清的是用户数据，不是字典）；
///   ③ 教练记忆 / 主动消息清成 0（上一轮定的口径，v25 不许弄丢）。
void main() {
  late AppDatabase db;
  late Directory docs;
  late Directory backups;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    docs = await Directory.systemTemp.createTemp('fittrack_wipe_character');
    backups = Directory(p.join(docs.path, 'backups'));
    await Directory(p.join(docs.path, 'photos')).create(recursive: true);
    await backups.create(recursive: true);
    // wipeAll 会先把 docs/fittrack.sqlite 打成包 → 磁盘上必须有这个文件
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

  test('清空后：character_id 回到默认 guga（v25 新列也一起重置）', () async {
    final settings = UserSettingsRepositoryImpl(db);
    // 先造一条"选过菲比"的设置
    await db.into(db.userSettings).insert(
        UserSettingsCompanion.insert(characterId: const Value('phoebe')));
    expect((await settings.get())?.characterId, 'phoebe');

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    // 行被整表删掉（user_settings 在 tableNames 里），再读就是"从没设过"
    final after = await settings.get();
    expect(after, isNull, reason: 'user_settings 应被清空');
    // 三条路径统一口径（C-3）：读不到 = 咕嘎
    expect(after?.characterId ?? 'guga', 'guga');

    // 库里不许残留任何 phoebe 值
    final rows = await db
        .customSelect('SELECT character_id FROM user_settings')
        .get();
    expect(rows.map((r) => r.data['character_id']), isNot(contains('phoebe')));
  });

  test('清空后：内置食物 / 内置模板仍在（新列不影响"先备份再清"的边界）',
      () async {
    final foodsBefore = (await db.select(db.foodLibrary).get()).length;
    final templatesBefore = (await db.select(db.workoutTemplates).get()).length;
    expect(foodsBefore, greaterThan(0));
    expect(templatesBefore, greaterThan(0));

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    final foodsAfter = await db.select(db.foodLibrary).get();
    final templatesAfter = await db.select(db.workoutTemplates).get();
    expect(foodsAfter.where((f) => !f.isCustom).length, foodsBefore,
        reason: '内置食物一条都不能少');
    expect(foodsAfter.where((f) => f.isCustom), isEmpty);
    expect(templatesAfter.where((t) => t.isRecommended).length,
        templatesBefore,
        reason: '内置模板要补齐到 5 个');
  });

  test('清空后：教练记忆 / 主动消息 / 周报缓存都是 0 条', () async {
    await db.into(db.coachMemories).insert(CoachMemoriesCompanion.insert(
          category: 'injury',
          topic: '左膝',
          content: '用户左膝有旧伤，避免深蹲',
          quote: '我左膝不太好',
          createdAt: Value(DateTime(2025, 3, 1)),
        ));
    await db.into(db.coachProactiveMessages).insert(
        CoachProactiveMessagesCompanion.insert(
          kind: 'weekly',
          dedupeKey: 'weekly-2025-03-02',
          content: '周三了，去练一次？',
          source: 'weekly',
          createdAt: Value(DateTime(2025, 3, 2)),
        ));

    await DataWipeService.wipeAll(db: db, docsDir: docs);

    expect(await db.select(db.coachMemories).get(), isEmpty);
    expect(await db.select(db.coachProactiveMessages).get(), isEmpty);
    expect(await db.select(db.weeklyReportCache).get(), isEmpty);
  });
}
