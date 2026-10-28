import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/migration_failure_marker.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fittrack_marker');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File markerFile() => File(p.join(dir.path, MigrationFailureMarker.fileName));

  group('MigrationFailureMarker 读写', () {
    test('没有标记文件时 read 返回 null（正常启动路径）', () async {
      expect(await MigrationFailureMarker.read(baseDir: dir), isNull);
    });

    test('record 写入后可读回，首次 attemptCount == 1', () async {
      final written = await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:day_overrides',
        baseDir: dir,
      );
      expect(written.attemptCount, 1);
      expect(markerFile().existsSync(), isTrue);

      final read = await MigrationFailureMarker.read(baseDir: dir);
      expect(read, isNotNull);
      expect(read!.fromVersion, 20);
      expect(read.targetVersion, 21);
      expect(read.failingStep, 'createTable:day_overrides');
      expect(read.attemptCount, 1);
    });

    test('连续 record 时 attemptCount 递增', () async {
      await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:weekly_reports',
        baseDir: dir,
      );
      final second = await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:weekly_reports',
        baseDir: dir,
      );
      expect(second.attemptCount, 2);
      final third = await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:weekly_reports',
        baseDir: dir,
      );
      expect(third.attemptCount, 3);
    });

    test('record 会替换上一次的失败步骤（永远反映最近一次）', () async {
      await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:weekly_reports',
        baseDir: dir,
      );
      await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'index:idx_food_log_date',
        baseDir: dir,
      );
      final read = await MigrationFailureMarker.read(baseDir: dir);
      expect(read!.failingStep, 'index:idx_food_log_date');
    });

    test('clear 之后 read 返回 null（成功迁移即删标记）', () async {
      await MigrationFailureMarker.record(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'addColumn:ai_health_override_count',
        baseDir: dir,
      );
      await MigrationFailureMarker.clear(baseDir: dir);
      expect(markerFile().existsSync(), isFalse);
      expect(await MigrationFailureMarker.read(baseDir: dir), isNull);
    });

    test('clear 在没有标记时也不抛（幂等）', () async {
      await MigrationFailureMarker.clear(baseDir: dir);
      await MigrationFailureMarker.clear(baseDir: dir);
      expect(await MigrationFailureMarker.read(baseDir: dir), isNull);
    });

    test('标记文件损坏时返回 corrupt 兜底值，不抛异常、不静默忽略', () async {
      await markerFile().writeAsString('{ this is not json');
      final read = await MigrationFailureMarker.read(baseDir: dir);
      expect(read, isNotNull);
      expect(read!.failingStep, 'marker-corrupt');
      expect(read.attemptCount, 1);
    });

    test('JSON 字段类型异常时不崩（宽容解析）', () async {
      await markerFile().writeAsString(jsonEncode({
        'fromVersion': '20',
        'targetVersion': 21.0,
        'failingStep': 42,
        'attemptCount': null,
        'at': 'not-a-date',
      }));
      final read = await MigrationFailureMarker.read(baseDir: dir);
      expect(read, isNotNull);
      expect(read!.fromVersion, 20);
      expect(read.targetVersion, 21);
      expect(read.failingStep, 'unknown');
      expect(read.attemptCount, 1);
    });
  });

  group('diagnostics（可安全截图/复制的诊断串）', () {
    test('包含目标版本与失败步骤，便于定位卡在哪条 DDL', () {
      final marker = MigrationFailureMarker(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'index:idx_food_log_date',
        attemptCount: 2,
        at: DateTime(2025, 3, 4, 5, 6),
      );
      final text = marker.diagnostics;
      expect(text, contains('21'));
      expect(text, contains('index:idx_food_log_date'));
      expect(text, contains('20'));
      expect(text, contains('2'));
    });

    test('不包含任何用户数据字段（只有版本/步骤/次数）', () {
      final marker = MigrationFailureMarker(
        fromVersion: 20,
        targetVersion: 21,
        failingStep: 'createTable:weekly_reports',
        attemptCount: 1,
        at: DateTime(2025, 3, 4),
      );
      final keys = marker.toJson().keys.toSet();
      expect(keys, {
        'fromVersion',
        'targetVersion',
        'failingStep',
        'attemptCount',
        'at',
      });
    });
  });
}
