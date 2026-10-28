import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';

void main() {
  test('smoke: temp-file NativeDatabase close -> reopen 数据仍在', () async {
    final dir = await Directory.systemTemp.createTemp('fittrack_smoke');
    final file = File(p.join(dir.path, 'smoke.sqlite'));
    try {
      final db1 = AppDatabase.withExecutor(NativeDatabase(file));
      await db1.customSelect('SELECT 1').get();
      await db1.into(db1.bodyMetrics).insert(BodyMetricsCompanion.insert(
            date: DateTime(2024, 1, 1),
            weightKg: 70.5,
          ));
      await db1.close();
      expect(file.existsSync(), isTrue);

      final db2 = AppDatabase.withExecutor(NativeDatabase(file));
      final rows = await db2.select(db2.bodyMetrics).get();
      expect(rows.length, 1);
      expect(rows.single.weightKg, 70.5);
      await db2.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
