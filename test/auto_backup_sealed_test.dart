import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/services/auto_backup_service.dart';

void main() {
  tearDown(DatabaseSeal.reset);

  group('db_replaced 存在时自动备份必须停', () {
    test('isDbReplaced == true → 返回 sealed，且一次 tick 都不做', () async {
      var ticks = 0;
      final result = await AutoBackupService.runIfNeeded(
        enabled: true,
        isDbReplaced: () async {
          ticks++;
          return true;
        },
      );
      expect(result, 'sealed');
      expect(ticks, 1, reason: '只做了一次"是否换过库"的判断');
    });

    test('封存态（DatabaseSeal.sealed）→ 也返回 sealed', () async {
      DatabaseSeal.seal();
      final result = await AutoBackupService.runIfNeeded(
        enabled: true,
        isDbReplaced: () async => false,
      );
      expect(result, 'sealed');
    });

    test('判断自身抛异常 → 按 sealed 处理（不确定就别备份）', () async {
      final result = await AutoBackupService.runIfNeeded(
        enabled: true,
        isDbReplaced: () async => throw StateError('io error'),
      );
      expect(result, 'sealed', reason: '判断不出来时备份可能读到半新半旧的数据，比不备份危险得多');
    });

    test('开关关闭时优先返回 disabled（不白跑判断）', () async {
      var calls = 0;
      final result = await AutoBackupService.runIfNeeded(
        enabled: false,
        isDbReplaced: () async {
          calls++;
          return true;
        },
      );
      expect(result, 'disabled');
      expect(calls, 0);
    });
  });
}
