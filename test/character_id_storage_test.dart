import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/data_wipe_service.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

/// 角色存储：三条默认路径都是咕嘎（C-3）+ 非法值不回写（C-4）
void main() {
  late AppDatabase db;
  late UserSettingsRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = UserSettingsRepositoryImpl(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('C-3 三条路径默认都是 guga', () {
    test('① 空库安装：还没建行 / 建了行都是 guga', () async {
      // 还没建设置行：get() 返回 null，读路径按 guga 渲染
      expect(await repo.get(), isNull);
      expect(CharacterCatalog.resolve(null, 0).id, CharacterId.guga);

      // 建了行（走 save 的任何一次写入）：DB 默认值兜底
      final saved = await repo.save(heightCm: 170);
      expect(saved.characterId, 'guga');
      expect(CharacterCatalog.resolve(saved.characterId, 0).id, CharacterId.guga);
    });

    test('② 老库升级：列默认值回填 guga（迁移细节见 migration_v25_test）', () async {
      // 直接插一行不带 character_id：等价于 ALTER TABLE 的 DEFAULT 回填
      await db.into(db.userSettings).insert(const UserSettingsCompanion());
      final row = await db.select(db.userSettings).getSingle();
      expect(row.characterId, 'guga');
    });

    test('③ wipe_all_data 之后回到 guga', () async {
      // 用户先选了糯糯
      await repo.saveCharacterId(CharacterId.nuonuo);
      expect((await repo.get())!.characterId, 'nuonuo');

      final docs = await Directory.systemTemp.createTemp('fittrack_v25_wipe');
      try {
        // wipeAll 会先打包 docs/fittrack.sqlite，先造一个真实文件库
        final fileDb = AppDatabase.withExecutor(
            NativeDatabase(File(p.join(docs.path, 'fittrack.sqlite'))));
        await fileDb.customSelect('SELECT 1').get();
        await fileDb.close();

        await DataWipeService.wipeAll(db: db, docsDir: docs);

        // user_settings 整表清空 ⇒ get() 为 null ⇒ 渲染 guga（= "还没选过"）
        expect(await repo.get(), isNull);
        expect(CharacterCatalog.resolve(null, 0).id, CharacterId.guga);
        expect(DataWipeService.tableNames, contains('user_settings'),
            reason: '清空能覆盖 character_id，靠的就是这张表在删除清单里');
      } finally {
        try {
          await docs.delete(recursive: true);
        } catch (_) {}
      }
    });
  });

  group('C-4 非法值不回写数据库', () {
    test('库里塞 nuonuo_v2：读得到、渲染咕嘎、库内原值不变', () async {
      await db.into(db.userSettings).insert(
            const UserSettingsCompanion(characterId: Value('nuonuo_v2')),
          );

      final first = await repo.get();
      expect(first!.characterId, 'nuonuo_v2',
          reason: '读路径原样返回原始字符串，不做修正');
      expect(CharacterCatalog.resolve(first.characterId, 0).id,
          CharacterId.guga,
          reason: '渲染按咕嘎（C1）');

      // 再读一次：库里必须还是脏值（降级可以显示错，但不许改数据）
      final second = await repo.get();
      expect(second!.characterId, 'nuonuo_v2');

      final raw = await db
          .customSelect('SELECT character_id FROM user_settings LIMIT 1')
          .getSingle();
      expect(raw.data['character_id'], 'nuonuo_v2');
    });

    test('同一份数据被渲染多次也不会被覆写（读路径无写副作用）', () async {
      await db.into(db.userSettings).insert(
            const UserSettingsCompanion(characterId: Value('GUGA')),
          );
      for (var i = 0; i < 5; i++) {
        final s = await repo.get();
        CharacterCatalog.resolve(s!.characterId, 3);
      }
      final raw = await db
          .customSelect('SELECT character_id FROM user_settings LIMIT 1')
          .getSingle();
      expect(raw.data['character_id'], 'GUGA');
    });
  });

  group('切换角色的写入口', () {
    test('saveCharacterId 落白名单值，且没有设置行时先建行', () async {
      expect(await repo.get(), isNull);
      await repo.saveCharacterId(CharacterId.phoebe);
      final saved = await repo.get();
      expect(saved, isNotNull, reason: '新用户也能换形象，不许静默失败');
      expect(saved!.characterId, 'phoebe');
    });

    test('连续切换：最后一次生效，只有一行', () async {
      await repo.saveCharacterId(CharacterId.nuonuo);
      await repo.saveCharacterId(CharacterId.phoebe);
      await repo.saveCharacterId(CharacterId.guga);
      final rows = await db.select(db.userSettings).get();
      expect(rows, hasLength(1), reason: '单用户单行，不许每次切角色插一行');
      expect(rows.single.characterId, 'guga');
    });

    test('切换不碰其他设置（昵称 / 身高都还在）', () async {
      // 先 save 一次建出行：saveNickname 在"没有设置行"时是 no-op
      await repo.save(heightCm: 172);
      await repo.saveNickname('小嘎');
      await repo.saveCharacterId(CharacterId.nuonuo);
      final saved = await repo.get();
      expect(saved!.nickname, '小嘎');
      expect(saved.heightCm, 172);
      expect(saved.characterId, 'nuonuo');
    });
  });
}
