import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auto_backup_service.dart';

/// 数据库救援服务：备份当前库 / 导出坏库 / 清理日志残留。
///
/// 这些操作**只做文件 IO**，不打开数据库 —— 因为使用场景恰恰是
/// 「数据库打不开」的降级态。任何走 Repository 的实现（例如 CSV 导出）
/// 在降级态都必然失败。
///
/// ⚠️ 这里**不再提供**「从备份恢复」：旧实现是 `findRestorableBackup()` 盲挑
/// `backups/` 里最新的一份直接 copy 覆盖，既用不上用户刚导出的文件、也不做任何
/// 校验，正是「恢复后得到空库」事故的原形态。恢复统一走
/// `RestoreService`（候选 → 校验链 → 原子替换）。
///
/// 行数控制：这里只放可复用的纯逻辑 + 文件操作，UI 文案留在降级页里。
class DatabaseRecoveryService {
  DatabaseRecoveryService._();

  /// 恢复前自动备份的前缀。
  ///
  /// ⚠️ `pre-restore-` 文件**不占** `AutoBackupService.keep` 的额度、
  /// 且永不被自动清理删除（见 `AutoBackupService._prune`）。否则用户恢复几次后，
  /// 安全网会正好在他最需要的时候被轮转干掉。
  static const String preRestorePrefix = 'pre-restore';

  /// 导出「打不开的库」时的文件名前缀（排查用，绝不删原文件）。
  static const String brokenPrefix = 'broken';

  /// 连点几次「再试一次」之后，把「先存一份数据」提到主按钮位置。
  static const int escalateAfterAttempts = 3;

  /// 时间戳格式：yyyyMMdd-HHmmss（按天+秒，同一秒内重复则追加 -2 由调用方保证）
  static String stamp(DateTime now) =>
      DateFormat('yyyyMMdd-HHmmss').format(now);

  /// 恢复前备份的文件名（纯函数，便于单测）
  static String preRestoreFileName(DateTime now) =>
      '$preRestorePrefix-${stamp(now)}.sqlite';

  /// 坏库导出的文件名（纯函数，便于单测）
  static String brokenFileName(DateTime now) =>
      '$brokenPrefix-${stamp(now)}.sqlite';

  /// 是否应当把「先存一份数据」升为主按钮（纯函数，便于单测）
  ///
  /// 注意：升级按钮**不是禁用**「再试一次」。空间不足这类偶发问题清完就好了，
  /// 禁用等于判死刑；只是不再用主按钮催用户点第 4 次。
  static bool shouldEscalateToBackup(int attemptCount) =>
      attemptCount >= escalateAfterAttempts;

  /// 与 [dbPath] 配套的 WAL 日志文件路径（纯函数，便于单测）。
  ///
  /// 恢复是「直接覆盖主文件」，若残留 `-wal` / `-shm`，SQLite 下次打开会把旧页
  /// 回放进新库里 —— 表现为「恢复后仍能查到已经不存在的照片/金额」。
  static List<String> journalPathsFor(String dbPath) => [
        '$dbPath-wal',
        '$dbPath-shm',
      ];

  /// 删除残留的 `-wal` / `-shm`（存在才删，返回实际删除的路径）。
  static Future<List<String>> cleanupJournalFiles(String dbPath) async {
    final deleted = <String>[];
    for (final path in journalPathsFor(dbPath)) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deleted.add(path);
        }
      } catch (_) {
        // 删不掉不让恢复流程失败：最坏情况是 SQLite 自己会忽略无效日志
      }
    }
    return deleted;
  }

  /// 数据库主文件路径（与 `database.dart` 的 `_openConnection` 保持同目录同位）
  static Future<String> databasePath() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'fittrack.sqlite');
  }

  /// 恢复前把当前库复制一份。**失败即中止**：不允许在「当前数据没备份」的
  /// 状态下动库。
  ///
  /// 返回备份文件路径；抛异常表示备份失败，调用方必须中止恢复。
  static Future<String> backupBeforeRestore({
    String? dbPath,
    DateTime? now,
    Directory? backupDir,
  }) async {
    final source = File(dbPath ?? await databasePath());
    if (!await source.exists()) {
      throw StateError('当前数据库文件不存在，无法备份');
    }
    final dir = backupDir ?? await AutoBackupService.backupDir();
    final target =
        File(p.join(dir.path, preRestoreFileName(now ?? DateTime.now())));
    await source.copy(target.path);
    return target.path;
  }

  /// 把打不开的库复制到备份目录供排查。**不删原文件**。
  static Future<String> exportBrokenDatabase({
    String? dbPath,
    DateTime? now,
    Directory? backupDir,
  }) async {
    final source = File(dbPath ?? await databasePath());
    if (!await source.exists()) {
      throw StateError('数据库文件不存在');
    }
    final dir = backupDir ?? await AutoBackupService.backupDir();
    final target =
        File(p.join(dir.path, brokenFileName(now ?? DateTime.now())));
    await source.copy(target.path);
    return target.path;
  }
}
