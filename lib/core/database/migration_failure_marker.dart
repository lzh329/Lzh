import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 迁移失败标记（**写文件，不是数据库列**）。
///
/// ⚠️ 为什么必须是文件：
/// 迁移失败时，「数据库」恰恰就是打不开的那个东西 —— `user_settings` 里的列
/// 既读不到也写不进。只有应用文档目录下的普通 JSON 文件在那个状态下仍然可读写。
/// 所以这个标记不能用 drift 表 / 列实现，任何「存到 DB 里更整洁」的改造都会让
/// 降级机制在真正需要它的时候失效。
///
/// 写入点：`AppDatabase.onUpgrade` 的 catch 里，**rethrow 之前**。
/// 清除点：`onCreate` / `onUpgrade` 成功之后（`clear()`）。
class MigrationFailureMarker {
  /// 与 `fittrack.sqlite` 同级，便于用户/我们直接索要这个文件。
  static const String fileName = 'migration_failure.json';

  /// 迁移起始版本
  final int fromVersion;

  /// 迁移目标版本
  final int targetVersion;

  /// **步骤级**失败位置，例如：
  /// `createTable:day_overrides` / `addColumn:ai_health_override_count` /
  /// `index:idx_food_log_date`。
  ///
  /// 为什么不是表级：v21 有 9 条 `CREATE INDEX`，如果只记表名，用户截图回来
  /// 我们仍然不知道是建表失败还是建索引失败，等于没有诊断信息。
  final String failingStep;

  /// 累计失败次数（每次写入时读取旧值 +1）。
  /// 用于区分「偶发」与「必现」；成功迁移一次后标记被删除，计数归零。
  final int attemptCount;

  /// 最近一次失败时间
  final DateTime at;

  const MigrationFailureMarker({
    required this.fromVersion,
    required this.targetVersion,
    required this.failingStep,
    required this.attemptCount,
    required this.at,
  });

  /// 标记文件存在但内容损坏时的兜底值：仍然要进降级页，不能静默忽略。
  factory MigrationFailureMarker.corrupt(DateTime at) {
    return MigrationFailureMarker(
      fromVersion: -1,
      targetVersion: -1,
      failingStep: 'marker-corrupt',
      attemptCount: 1,
      at: at,
    );
  }

  /// 面向用户的诊断描述（不含任何用户数据，可安全截图/复制）。
  String get diagnostics => '目标版本 $targetVersion，'
      '失败步骤 $failingStep，'
      '起始版本 $fromVersion，'
      '第 $attemptCount 次';

  factory MigrationFailureMarker.fromJson(Map<String, dynamic> json) {
    return MigrationFailureMarker(
      fromVersion: _asInt(json['fromVersion']),
      targetVersion: _asInt(json['targetVersion']),
      failingStep: json['failingStep'] is String
          ? json['failingStep'] as String
          : 'unknown',
      attemptCount: _asInt(json['attemptCount'], fallback: 1),
      at: _asDate(json['at']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'fromVersion': fromVersion,
        'targetVersion': targetVersion,
        'failingStep': failingStep,
        'attemptCount': attemptCount,
        'at': at.toIso8601String(),
      };

  // ───────────────────── 文件操作 ─────────────────────

  /// 标记文件路径。`baseDir` 仅供单测注入（生产用应用文档目录）。
  static Future<File> markerFile({Directory? baseDir}) async {
    final dir = baseDir ?? await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// 读标记。没有标记返回 null；**任何异常都不许抛给启动流程**。
  static Future<MigrationFailureMarker?> read({Directory? baseDir}) async {
    try {
      final file = await markerFile(baseDir: baseDir);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return MigrationFailureMarker.fromJson(decoded);
      }
      return MigrationFailureMarker.corrupt(DateTime.now());
    } catch (_) {
      // 文件损坏 / 磁盘错误：既不静默忽略（否则用户会在坏掉的 App 里打转），
      // 也不向上抛（否则降级页自己把启动流程搞崩）。
      return MigrationFailureMarker.corrupt(DateTime.now());
    }
  }

  /// 记录一次失败（读取旧计数 +1）。
  ///
  /// 实现说明：先写 `.tmp` 再 `rename`，避免写到一半断电留下半截 JSON，
  /// 让「标记文件」本身变成新的故障源。
  static Future<MigrationFailureMarker> record({
    required int fromVersion,
    required int targetVersion,
    required String failingStep,
    Directory? baseDir,
  }) async {
    var attempt = 1;
    try {
      final previous = await read(baseDir: baseDir);
      if (previous != null && previous.attemptCount > 0) {
        attempt = previous.attemptCount + 1;
      }
    } catch (_) {
      attempt = 1;
    }

    final marker = MigrationFailureMarker(
      fromVersion: fromVersion,
      targetVersion: targetVersion,
      failingStep: failingStep,
      attemptCount: attempt,
      at: DateTime.now(),
    );

    final file = await markerFile(baseDir: baseDir);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(marker.toJson()), flush: true);
    await temp.rename(file.path);
    return marker;
  }

  /// 迁移成功后清除标记（注意：`delete` 前先判存在，避免 Android 上抛
  /// FileSystemException 把成功路径也变成失败路径）。
  static Future<void> clear({Directory? baseDir}) async {
    try {
      final file = await markerFile(baseDir: baseDir);
      if (await file.exists()) await file.delete();
      final temp = File('${file.path}.tmp');
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // 清不掉标记不影响启动正确性（下次成功迁移还会再清一次）
    }
  }

  @override
  String toString() => 'MigrationFailureMarker(${toJson()})';
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime _asDate(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  return DateTime.now();
}
