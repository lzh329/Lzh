/// 启动期加固：所有可能失败的动作都**不许**把首帧搞挂。
///
/// 历史 bug（体检报告 #6 + 白屏）：
/// 旧 `main.dart` 在 `runApp` 之前 `await` 了一次数据库查询，且没有 try/catch ——
/// 只要数据库打不开（迁移失败 / 磁盘满 / 文件损坏），异常就抛在 runApp 之前，
/// 用户看到的是**白屏或永远卡在启动图**，连一句解释都没有。
/// 同时它内联 new 了**第二个** `AppDatabase`（与 providers 的那个并存，
/// 两个后台 isolate，且这个永不 close）。
///
/// 现在：全局只打开一个实例 + 打开失败一律进降级页。
///
/// 决策顺序（顺序不可换）：
/// 1. 读 marker（纯文件 IO，不碰数据库）；
/// 2. 没有 marker → 直接进正常 App（打开失败由第 4 步兜底）；
/// 3. 有 marker → 读数据库文件头的 `user_version` 判定三态：
///    - 等于当前版本 → **僵尸 marker**（迁移其实成功了，只是没删干净）
///      → 删 marker、正常启动。兜底机制不能自己变成故障源；
///    - 小于当前版本 / 读不出来 → 真失败 → 降级页；
///    - 大于当前版本 → 数据是更新版本 App 造的 → 降级页
///      （**绝不**当僵尸删掉，否则会把版本号写回旧值，数据更难救）；
/// 4. 真去打开一次库；抛异常也进降级页
///    （覆盖「不是迁移失败，是库根本打不开」这条更宽的路径）；
/// 5. 通知初始化，失败忽略。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../features/migration/presentation/pages/migration_failure_page.dart';
import 'database/database.dart';
import 'database/database_health.dart';
import 'database/migration_failure_marker.dart';
import 'services/notification_service.dart';

/// 数据库打开器（可注入，便于单测）
typedef DatabaseOpener = Future<void> Function();

/// 数据库版本探测器（可注入，便于单测）
typedef UserVersionProbe = Future<int?> Function();

Future<void> _defaultInitNotifications() => NotificationService().init();

/// 用真实 `AppDatabase` 打开一次库（会触发迁移）。
///
/// 打开成功后立即 close：真正的长生命周期实例由 `databaseProvider` 持有，
/// 这里只负责「迁移能不能跑通」+「失败要能被捕获」。
Future<void> _defaultOpenDatabase() async {
  final db = AppDatabase();
  try {
    await db.customSelect('SELECT 1').get();
  } finally {
    await db.close();
  }
}

Future<int?> _defaultProbeUserVersion() async {
  final docs = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(docs.path, 'fittrack.sqlite'));
  return DatabaseFileHealth.readUserVersion(dbFile);
}

/// 构造启动根 widget（可注入全部副作用，便于单测）。
Future<Widget> buildStartupRoot({
  Future<MigrationFailureMarker?> Function() readMarker =
      MigrationFailureMarker.read,
  UserVersionProbe probeUserVersion = _defaultProbeUserVersion,
  DatabaseOpener openDatabase = _defaultOpenDatabase,
  Future<void> Function() initNotifications = _defaultInitNotifications,
  int schemaVersion = kSchemaVersion,
}) async {
  // ── 1) 先读 marker（纯文件 IO） ──
  MigrationFailureMarker? marker;
  try {
    marker = await readMarker();
  } catch (_) {
    marker = null; // 读 marker 自身失败不该挡住启动
  }

  // ── 2/3) 判定 marker 是否僵尸 ──
  if (marker != null) {
    var verdict = MarkerVerdict.genuine;
    try {
      final userVersion = await probeUserVersion();
      verdict = judgeMarker(
        userVersion: userVersion,
        schemaVersion: schemaVersion,
      );
    } catch (_) {
      verdict = MarkerVerdict.genuine;
    }

    if (verdict == MarkerVerdict.zombie) {
      // 迁移其实成功了，只是 marker 没删掉 → 清掉，正常启动
      await MigrationFailureMarker.clear();
    } else {
      return DatabaseFailureApp(marker: marker, verdict: verdict);
    }
  }

  // ── 4) 打开数据库；失败同样进降级页 ──
  try {
    await openDatabase();
  } catch (_) {
    final failure = marker ??
        MigrationFailureMarker(
          fromVersion: -1,
          targetVersion: schemaVersion,
          failingStep: 'openDatabase',
          attemptCount: 1,
          at: DateTime.now(),
        );
    return DatabaseFailureApp(marker: failure);
  }

  // ── 5) 通知初始化失败不影响启动 ──
  try {
    await initNotifications();
  } catch (_) {
    // 通知权限被拒 / 平台通道异常：忽略，App 仍然可用
  }

  return const ProviderScope(child: FitTrackApp());
}
