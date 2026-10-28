import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../database/db_replaced_marker.dart';

/// 换库后的「消解」（重建连接 + 清标记）。
///
/// 两处调用：bootstrap 启动时、`AppLifecycleState.resumed` 时。
/// 两处都可能几乎同时触发（用户从备份页返回 + 系统 resume），所以必须**单飞**：
/// 连发两次只能重建一次，否则第二次会把刚建好的连接关掉、留下一个已关的实例。
class DatabaseResolver {
  DatabaseResolver._();

  static Future<bool>? _inFlight;

  /// 是否有消解在进行中（单测用）
  static bool get busy => _inFlight != null;

  /// 单测用：清空单飞状态
  static void resetForTesting() => _inFlight = null;

  /// 执行一次消解。
  ///
  /// 返回 true = 消解成功（标记已清、封存已解除）；false = 失败（**保留标记**，
  /// 下次启动或下次 resume 会自然重试，用户不会白屏）。
  ///
  /// [closeCurrent] / [reopen] 由调用方注入（生产里是 `ref.read(databaseProvider)`
  /// 的 close + invalidate），这样这段逻辑可以纯单测。
  static Future<bool> resolve({
    required Future<void> Function() closeCurrent,
    required Future<void> Function() reopen,
    Directory? markerDir,
  }) {
    final running = _inFlight;
    if (running != null) return running;

    final task = _run(
      closeCurrent: closeCurrent,
      reopen: reopen,
      markerDir: markerDir,
    );
    _inFlight = task;
    return task.whenComplete(() => _inFlight = null);
  }

  static Future<bool> _run({
    required Future<void> Function() closeCurrent,
    required Future<void> Function() reopen,
    Directory? markerDir,
  }) async {
    // 先 close 再重建：顺序反了旧的后台 isolate 永远不会关闭（泄漏），
    // 而且旧句柄还握着可能已被 rename 的文件。
    try {
      await closeCurrent();
    } catch (_) {
      // 旧实例可能本来就没打开成功
    }

    try {
      await reopen();
    } catch (_) {
      // 消解失败：**保留标记**，让下次启动/下次 resume 自然重试。
      // 进封存态而不是白屏 —— 用户至少看得到一句话和一条出路。
      DatabaseSeal.seal();
      return false;
    }

    // 新库打开成功才清标记（标记语义 = "还没确认新库可用"）
    await DbReplacedMarker.clear(baseDir: markerDir);
    DatabaseSeal.unseal();
    return true;
  }

  /// 生产环境用的便捷入口：默认标记目录 = 应用文档目录。
  static Future<bool> resolveFromDocuments({
    required Future<void> Function() closeCurrent,
    required Future<void> Function() reopen,
  }) async {
    Directory? dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } catch (_) {
      dir = null;
    }
    return resolve(
      closeCurrent: closeCurrent,
      reopen: reopen,
      markerDir: dir,
    );
  }
}
