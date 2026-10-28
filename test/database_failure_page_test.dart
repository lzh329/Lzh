import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/bootstrap.dart';
import 'package:fittrack/core/database/database_health.dart';
import 'package:fittrack/core/database/migration_failure_marker.dart';
import 'package:fittrack/features/migration/presentation/pages/migration_failure_page.dart';

MigrationFailureMarker _marker({
  int attemptCount = 1,
  String failingStep = 'createTable:weekly_report_cache',
}) {
  return MigrationFailureMarker(
    fromVersion: 20,
    targetVersion: 21,
    failingStep: failingStep,
    attemptCount: attemptCount,
    at: DateTime(2025, 3, 4, 5, 6),
  );
}

void main() {
  group('buildStartupRoot 启动决策', () {
    test('没有 marker 且库能打开 → 正常 App', () async {
      final root = await buildStartupRoot(
        readMarker: () async => null,
        probeUserVersion: () async => 20,
        openDatabase: () async {},
        initNotifications: () async {},
        schemaVersion: 20,
      );
      expect(root, isA<ProviderScope>());
      expect(root, isNot(isA<DatabaseFailureApp>()));
    });

    test('打开库抛异常 → 降级页（覆盖「不是迁移失败，是库打不开」）', () async {
      final root = await buildStartupRoot(
        readMarker: () async => null,
        probeUserVersion: () async => 20,
        openDatabase: () async => throw StateError('disk full'),
        initNotifications: () async {},
        schemaVersion: 20,
      );
      expect(root, isA<DatabaseFailureApp>());
      final app = root as DatabaseFailureApp;
      expect(app.marker.failingStep, 'openDatabase');
      expect(app.marker.targetVersion, 20);
    });

    test('marker 真实 + 库版本落后 → 降级页', () async {
      final root = await buildStartupRoot(
        readMarker: () async => _marker(),
        probeUserVersion: () async => 20,
        openDatabase: () async {},
        initNotifications: () async {},
        schemaVersion: 21,
      );
      expect(root, isA<DatabaseFailureApp>());
    });

    test('僵尸 marker（库版本已等于 schemaVersion）→ 删 marker 并正常启动', () async {
      var opened = false;
      final root = await buildStartupRoot(
        readMarker: () async => _marker(attemptCount: 3),
        probeUserVersion: () async => 21,
        openDatabase: () async => opened = true,
        initNotifications: () async {},
        schemaVersion: 21,
      );
      expect(root, isA<ProviderScope>(),
          reason: '兜底机制不能自己变成故障源：迁移其实成功了就必须正常启动');
      expect(opened, isTrue);
    });

    test('库版本比 App 新 → 降级页且 verdict==newerData（不许当僵尸删）', () async {
      final root = await buildStartupRoot(
        readMarker: () async => _marker(),
        probeUserVersion: () async => 22,
        openDatabase: () async {},
        initNotifications: () async {},
        schemaVersion: 21,
      );
      expect(root, isA<DatabaseFailureApp>());
      expect((root as DatabaseFailureApp).verdict, MarkerVerdict.newerData);
    });

    test('读 marker 抛异常 → 不挡住启动', () async {
      final root = await buildStartupRoot(
        readMarker: () async => throw StateError('io error'),
        probeUserVersion: () async => 20,
        openDatabase: () async {},
        initNotifications: () async {},
        schemaVersion: 20,
      );
      expect(root, isA<ProviderScope>());
    });

    test('通知初始化抛异常 → 不挡住启动', () async {
      final root = await buildStartupRoot(
        readMarker: () async => null,
        probeUserVersion: () async => 20,
        openDatabase: () async {},
        initNotifications: () async => throw StateError('no permission'),
        schemaVersion: 20,
      );
      expect(root, isA<ProviderScope>());
    });
  });

  group('DatabaseFailurePage 渲染与按钮层级', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required MigrationFailureMarker marker,
      MarkerVerdict verdict = MarkerVerdict.genuine,
    }) async {
      await tester.pumpWidget(
        DatabaseFailureApp(marker: marker, verdict: verdict),
      );
      await tester.pump();
    }

    testWidgets('首屏文案必须出现「你的记录都还在」', (tester) async {
      await pumpPage(tester, marker: _marker());
      expect(
        find.textContaining('你的记录都还在'),
        findsOneWidget,
        reason: '本地无后端，用户看到升级失败第一反应是「我数据没了」',
      );
      expect(find.textContaining('可以再试一次'), findsOneWidget);
    });

    testWidgets('诊断区显示「卡在第几步」（步骤级，不是表级）', (tester) async {
      await pumpPage(tester,
          marker: _marker(failingStep: 'index:idx_food_log_date'));
      expect(find.textContaining('index:idx_food_log_date'), findsOneWidget);
      expect(find.textContaining('卡在第几步'), findsOneWidget);
    });

    testWidgets('1~3 次失败：「从备份恢复」为主按钮', (tester) async {
      await pumpPage(tester, marker: _marker(attemptCount: 2));
      expect(find.text('从备份恢复'), findsOneWidget);
      expect(find.text('先存一份数据'), findsOneWidget);
      expect(find.text('先用备份恢复，再排查'), findsNothing);
    });

    testWidgets('第 3 次之后：「先存一份数据」提到主位但不禁用「再试一次」', (tester) async {
      await pumpPage(tester, marker: _marker(attemptCount: 3));
      expect(find.text('还不行，先把数据存一份'), findsOneWidget);
      expect(find.text('先用备份恢复，再排查'), findsOneWidget);

      // 「再试一次」仍在且可点（偶发问题清完就好了，禁用等于判死刑）
      final retry =
          tester.widget<TextButton>(find.widgetWithText(TextButton, '再试一次'));
      expect(retry.onPressed, isNotNull);
    });

    testWidgets('库版本比 App 新：文案改「更新版本」且给出覆盖警告', (tester) async {
      await pumpPage(
        tester,
        marker: _marker(),
        verdict: MarkerVerdict.newerData,
      );
      expect(find.textContaining('更新版本'), findsOneWidget);
      expect(find.textContaining('会覆盖新版本数据'), findsOneWidget);
    });
  });
}
