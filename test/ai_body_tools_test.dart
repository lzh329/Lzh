import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'fake_database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// #7 身体信息 CRUD 三工具（真内存库）
void main() {
  late AppDatabase db;
  late AiToolExecutor executor;

  Future<BodyMetricEntity> seed({
    required DateTime date,
    required double weightKg,
    double? waistCm,
  }) async {
    final id = await db.into(db.bodyMetrics).insert(
          BodyMetricsCompanion.insert(
            date: date,
            weightKg: weightKg,
            waistCm: Value(waistCm),
          ),
        );
    return BodyMetricEntity(
      id: id,
      date: date,
      weightKg: weightKg,
      waistCm: waistCm,
    );
  }

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    executor = AiToolExecutor(repos: fakeToolRepos(db));
  });

  tearDown(() async => db.close());

  group('query_measurements（只读）', () {
    test('返回最近记录 + 各部位最新值；无记录的部位是 null 而不是 0', () async {
      await seed(
        date: DateTime(2025, 3, 1),
        weightKg: 72,
        waistCm: 88,
      );
      await seed(date: DateTime(2025, 3, 5), weightKg: 70.5);

      final result = await executor.execute(const AiToolCall(
        id: 'q1',
        name: AiToolSpecs.queryMeasurements,
        argumentsJson: '{}',
      ));

      final json = jsonDecode(result) as Map<dynamic, dynamic>;
      final latest = json['latest'];
      expect(json['ok'], isTrue);
      expect(json['count'], 2);

      // 最新值：体重取 3/5 的 70.5，腰围取 3/1 的 88（3/5 没量）
      expect(latest['weight_kg'], 70.5);
      expect(latest['waist_cm'], 88);
      expect(latest['hip_cm'], isNull, reason: '从没量过臀围 → null，不许给 0');
      expect(latest['chest_cm'], isNull);
    });
  });

  group('update_measurement（写需确认）', () {
    test('preview 列出改前 → 改后，needsConfirm', () async {
      final e = await seed(
        date: DateTime(2025, 3, 5),
        weightKg: 70.5,
        waistCm: 88,
      );

      final preview = await executor.preview(AiToolCall(
        id: 'u0',
        name: AiToolSpecs.updateMeasurement,
        argumentsJson: '{"id":${e.id},"part":"waist","value":85}',
      ));
      expect(preview.needsConfirm, isTrue);
      expect(preview.detail, contains('腰 88.0cm'));
      expect(preview.detail, contains('85.0cm'), reason: '确认卡必须让用户看到改前 → 改后');
      expect(preview.isDestructive, isFalse);
    });

    test('execute 按 id 改腰围，其余字段保持不变', () async {
      final e = await seed(
        date: DateTime(2025, 3, 5),
        weightKg: 70.5,
        waistCm: 88,
      );

      await executor.execute(AiToolCall(
        id: 'u1',
        name: AiToolSpecs.updateMeasurement,
        argumentsJson: '{"id":${e.id},"part":"waist","value":85}',
      ));

      final row = await (db.select(db.bodyMetrics)
            ..where((t) => t.id.equals(e.id)))
          .getSingle();
      expect(row.waistCm, 85);
      expect(row.weightKg, 70.5, reason: '没改的字段不能被清掉');
    });

    test('按 日期+部位 定位也能改', () async {
      final e = await seed(date: DateTime(2025, 3, 5), weightKg: 70.5);

      await executor.execute(const AiToolCall(
        id: 'u2',
        name: AiToolSpecs.updateMeasurement,
        argumentsJson: '{"date":"2025-03-05","part":"weight","value":69.8}',
      ));

      final row = await (db.select(db.bodyMetrics)
            ..where((t) => t.id.equals(e.id)))
          .getSingle();
      expect(row.weightKg, 69.8);
    });
  });

  group('delete_measurement（危险）', () {
    test('在 destructiveTools 里（红卡）', () {
      expect(
        AiToolSpecs.destructiveTools.contains(AiToolSpecs.deleteMeasurement),
        isTrue,
      );
      expect(AiToolSpecs.writeTools, contains(AiToolSpecs.deleteMeasurement));
      expect(AiToolSpecs.readOnlyTools,
          isNot(contains(AiToolSpecs.deleteMeasurement)));
    });

    test('preview 是危险样式并列出将删内容', () async {
      final e = await seed(date: DateTime(2025, 3, 5), weightKg: 70.5);
      final preview = await executor.preview(AiToolCall(
        id: 'd0',
        name: AiToolSpecs.deleteMeasurement,
        argumentsJson: '{"id":${e.id}}',
      ));
      expect(preview.isDestructive, isTrue);
      expect(preview.needsConfirm, isTrue);
      expect(preview.detail, contains('70.5kg'));
    });

    test('execute 真删', () async {
      final e = await seed(date: DateTime(2025, 3, 5), weightKg: 70.5);
      await executor.execute(AiToolCall(
        id: 'd1',
        name: AiToolSpecs.deleteMeasurement,
        argumentsJson: '{"id":${e.id}}',
      ));
      final rows = await db.select(db.bodyMetrics).get();
      expect(rows, isEmpty);
    });
  });
}
