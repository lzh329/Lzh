import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/backup_candidate_service.dart';
import 'package:fittrack/core/services/backup_service.dart';

/// 造一个真实可读的库（关键表都在 → 能被当成合法候选）
Future<void> seedDb(File file, {int bodyMetrics = 0, int workouts = 0}) async {
  final db = AppDatabase.withExecutor(NativeDatabase(file));
  await db.customSelect('SELECT 1').get();
  for (var i = 0; i < bodyMetrics; i++) {
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
          date: DateTime(2025, 3, 1 + i),
          weightKg: 70.0 + i,
        ));
  }
  for (var i = 0; i < workouts; i++) {
    await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          date: DateTime(2025, 3, 1 + i),
          type: 'strength',
        ));
  }
  await db.close();
}

void main() {
  late Directory root;
  late Directory docs;
  late Directory downloads;
  late Directory backups;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fittrack_candidates');
    docs = Directory(p.join(root.path, 'docs'));
    downloads = Directory(p.join(root.path, 'downloads'));
    backups = Directory(p.join(docs.path, 'backups'));
    await downloads.create(recursive: true);
    await backups.create(recursive: true);
  });

  tearDown(() async {
    try {
      if (await root.exists()) await root.delete(recursive: true);
    } catch (_) {}
  });

  File at(Directory dir, String name) => File(p.join(dir.path, name));

  test('三类来源都能列出，且按时间倒序', () async {
    // 导出文件：用户刚导出的那份（真实事故里它被完全忽略）
    final exported = at(downloads, 'fittrack_backup_20251031_235600.sqlite');
    await seedDb(exported, bodyMetrics: 3, workouts: 5);
    await exported.setLastModified(DateTime(2025, 10, 31, 23, 56));

    // 自动备份：上一轮"空库时代"的备份
    final auto = at(backups, 'fittrack_backup_20250301_080000.sqlite');
    await seedDb(auto); // 空库
    await auto.setLastModified(DateTime(2025, 3, 1, 8));

    // 恢复前副本：用户真正丢数据的地方
    final pre = at(backups, 'pre-restore-20251001-120000.sqlite');
    await seedDb(pre, bodyMetrics: 1);
    await pre.setLastModified(DateTime(2025, 10, 1, 12));

    // latest 镜像只是"最新时间戳备份"的副本，不该重复出现
    await at(backups, 'fittrack_backup_latest.sqlite').writeAsBytes([0]);

    final list = await BackupCandidateService.listCandidates(
      docsDir: docs,
      downloadDir: downloads,
      backupsDir: backups,
    );

    expect(list.length, 3, reason: 'latest 镜像不算独立候选');
    expect(
      list.map((c) => c.fileName).toList(),
      [
        'fittrack_backup_20251031_235600.sqlite',
        'pre-restore-20251001-120000.sqlite',
        'fittrack_backup_20250301_080000.sqlite',
      ],
      reason: '必须按时间倒序，最近的那份排最前',
    );
    expect(list[0].kind, BackupSourceKind.export);
    expect(list[1].kind, BackupSourceKind.preRestore);
    expect(list[2].kind, BackupSourceKind.autoBackup);

    // 行数是"只读统计"出来的真实值
    expect(list[0].counts!.bodyMetrics, 3);
    expect(list[0].counts!.workouts, 5);
    expect(list[0].readable, isTrue);
    expect(list[2].counts!.isEmpty, isTrue, reason: '空库备份必须被判成空');
  });

  test('探测候选时绝不修改原件（大小与内容不变）', () async {
    final file = at(downloads, 'fittrack_backup_20251031_235600.sqlite');
    await seedDb(file, bodyMetrics: 2);
    final sizeBefore = await file.length();
    final bytesBefore = await file.readAsBytes();

    await BackupCandidateService.listCandidates(
      docsDir: docs,
      downloadDir: downloads,
      backupsDir: backups,
    );

    expect(await file.length(), sizeBefore);
    expect(await file.readAsBytes(), bytesBefore);
    expect(File('${file.path}-wal').existsSync(), isFalse);
    expect(File('${file.path}-journal').existsSync(), isFalse);
  });

  test('坏文件标成不可读，不会让整份列表失败', () async {
    await at(downloads, 'fittrack_backup_20250101_000000.sqlite')
        .writeAsBytes([1, 2, 3, 4]);

    final list = await BackupCandidateService.listCandidates(
      docsDir: docs,
      downloadDir: downloads,
      backupsDir: backups,
    );

    expect(list.length, 1);
    expect(list.single.readable, isFalse);
    expect(list.single.counts, isNull);
  });

  test('目录读不到（不存在）时只是少几项，不抛异常', () async {
    final list = await BackupCandidateService.listCandidates(
      docsDir: docs,
      downloadDir: Directory(p.join(root.path, 'nope')),
      backupsDir: Directory(p.join(root.path, 'nope2')),
    );
    expect(list, isEmpty);
  });

  group('恢复前的风险判定（纯逻辑）', () {
    BackupCandidate candidate({
      BackupCounts? counts,
      bool readable = true,
      int? userVersion = kSchemaVersion,
      BackupSourceKind kind = BackupSourceKind.autoBackup,
    }) {
      return BackupCandidate(
        path: '/tmp/fittrack_backup_20251031_235600.sqlite',
        kind: kind,
        modifiedAt: DateTime(2025, 10, 31, 23, 56),
        sizeBytes: 138000,
        counts: counts,
        userVersion: userVersion,
        readable: readable,
      );
    }

    test('候选是空库 + 当前库有数据 → 高风险 + 文案点名"会清空"', () {
      final preview = RestorePreview.of(
        candidate: candidate(counts: BackupCounts.zero),
        current: const BackupCounts(workouts: 5, bodyMetrics: 3, photos: 2),
      );

      expect(preview.destructive, isTrue,
          reason: '这就是上次事故的组合：空库覆盖有数据的库');
      expect(preview.hardWarning, isNotNull);
      expect(preview.hardWarning!, contains('清空'));
      expect(preview.hardWarning!, contains('5 次训练'));
      expect(preview.summary, contains('10-31 23:56'));
      expect(preview.summary, contains('体重 0 条'));
      expect(preview.summary, contains('体重 3'),
          reason: '确认文案必须把当前库的行数摆出来做对比');
    });

    test('候选有数据 → 不是高风险，但照样给出行数对比', () {
      final preview = RestorePreview.of(
        candidate: candidate(
          counts: const BackupCounts(workouts: 4, bodyMetrics: 2, photos: 1),
        ),
        current: const BackupCounts(workouts: 0, bodyMetrics: 0, photos: 0),
      );

      expect(preview.destructive, isFalse);
      expect(preview.hardWarning, isNull);
      expect(preview.summary, contains('训练 4 次'));
    });

    test('空库候选一律判高风险：不看当前行数（降级态读不出当前行数）', () {
      // 当前库也是空的：仍然判高风险 —— "用空库覆盖"不需要知道当前有多少条
      final bothEmpty = RestorePreview.of(
        candidate: candidate(counts: BackupCounts.zero),
        current: BackupCounts.zero,
      );
      expect(bothEmpty.destructive, isTrue);
      expect(bothEmpty.hardWarning, isNotNull);

      // 降级态（读不出当前行数）：同样必须红
      final degraded = RestorePreview.of(
        candidate: candidate(counts: BackupCounts.zero),
        current: null,
      );
      expect(degraded.destructive, isTrue,
          reason: '库打不开时更不能把"空库覆盖"当成普通恢复');
      expect(degraded.hardWarning, isNotNull);
      expect(degraded.hardWarning!, contains('清空'));
      expect(degraded.summary, isNot(contains('（体重 0 /')),
          reason: '拿不到当前行数就不要编一段对比出来');
    });

    test('候选读不出 → 强警告说明会在校验阶段被拒', () {
      final preview = RestorePreview.of(
        candidate: candidate(counts: null, readable: false, userVersion: null),
        current: const BackupCounts(bodyMetrics: 1),
      );
      expect(preview.destructive, isFalse);
      expect(preview.hardWarning!, contains('校验'));
    });

    test('行数统计不出来（zip 缺 manifest）→ 只提示无法对比，不当成空库', () {
      final preview = RestorePreview.of(
        candidate: candidate(counts: null),
        current: const BackupCounts(bodyMetrics: 1),
      );
      expect(preview.destructive, isFalse,
          reason: '"不知道"不等于"是空的"，不能按高风险拦');
      expect(preview.notes.join(), contains('无法'));
    });

    test('备份比 App 新 → 提示会被拒绝', () {
      final preview = RestorePreview.of(
        candidate: candidate(
          counts: const BackupCounts(bodyMetrics: 1),
          userVersion: kSchemaVersion + 1,
        ),
        current: const BackupCounts(bodyMetrics: 1),
      );
      expect(preview.hardWarning!, contains('更新版本'));
    });

    test('裸库候选会提示照片不会跟着恢复', () {
      final preview = RestorePreview.of(
        candidate: candidate(
          counts: const BackupCounts(bodyMetrics: 1),
          kind: BackupSourceKind.export,
        ),
        current: const BackupCounts(bodyMetrics: 1),
      );
      expect(preview.notes.join(), contains('照片'));
    });
  });

  test('zip 备份包读 manifest 里的行数，且不当成裸库', () async {
    final dbFile = File(p.join(docs.path, 'fittrack.sqlite'));
    await seedDb(dbFile, bodyMetrics: 2);
    final photos = Directory(p.join(docs.path, 'photos'));
    await photos.create(recursive: true);
    await File(p.join(photos.path, 'a.jpg')).writeAsBytes([1]);

    final archive = await BackupService.createArchive(
      dbPath: dbFile.path,
      photosDir: photos,
      outputDir: backups,
      tableCounts: {'body_metrics': 2, 'photos': 1},
    );

    final list = await BackupCandidateService.listCandidates(
      docsDir: docs,
      downloadDir: downloads,
      backupsDir: backups,
    );
    final zip = list.firstWhere((c) => c.path == archive.path);

    expect(zip.kind, BackupSourceKind.archive);
    expect(zip.readable, isTrue);
    expect(zip.counts!.bodyMetrics, 2);
    expect(zip.counts!.photos, 1);
    expect(zip.isArchive, isTrue);
  });
}
