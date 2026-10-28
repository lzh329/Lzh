import 'dart:io';
import 'dart:typed_data';

/// SQLite 数据库文件健康探测 —— **不打开数据库**。
///
/// 为什么不能用「试着打开 drift 库」来判断：
/// 打开 drift 库会触发迁移（`ensureOpen` → 读 `user_version` → 算
/// `hadUpgrade` → 调 `onUpgrade`）。用故障机制去自检，可能再次失败、甚至卡住，
/// 把「僵尸 marker」的诊断变成新的故障点。
///
/// 所以这里直接读 SQLite 文件头的 `user_version`：
/// - 偏移 0~15：魔数 `SQLite format 3\0`
/// - 偏移 60~63：`user_version`（**4 字节大端**整数，由 SQLite 文件格式规定）
///
/// 不打开数据库、不触发迁移、不引新依赖（`dart:io` + `ByteData` 足够）。
class DatabaseFileHealth {
  DatabaseFileHealth._();

  /// 文件头魔数长度
  static const int headerMagicLength = 16;

  /// `user_version` 在文件头里的偏移
  static const int userVersionOffset = 60;

  /// 读取文件头 64 字节所需的长度
  static const int minimumHeaderLength = 64;

  /// SQLite 文件魔数（ASCII `SQLite format 3` + 结束 0）
  static const String sqliteMagic = 'SQLite format 3';

  /// 读取数据库文件的 `user_version`。
  ///
  /// 返回 null 表示「读不出来」：文件不存在、长度不足 64 字节、魔数不对
  /// （不是 SQLite 文件）。调用方必须把 null 当作「无法判断」而不是「健康的」。
  static Future<int?> readUserVersion(File file) async {
    try {
      if (!await file.exists()) return null;
      final handle = await file.open();
      try {
        final header = await handle.read(minimumHeaderLength);
        if (header.length < minimumHeaderLength) return null;
        if (!_hasSqliteMagic(header)) return null;
        return _readUserVersion(header);
      } finally {
        await handle.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// 从已读出的文件头字节解析 `user_version`（纯函数，便于单测）。
  static int? parseUserVersion(Uint8List header) {
    if (header.length < minimumHeaderLength) return null;
    if (!_hasSqliteMagic(header)) return null;
    return _readUserVersion(header);
  }

  static bool _hasSqliteMagic(Uint8List header) {
    // 前 15 字节是 "SQLite format 3"，第 16 字节是 0
    final prefix = String.fromCharCodes(header.sublist(0, sqliteMagic.length));
    return prefix == sqliteMagic;
  }

  static int _readUserVersion(Uint8List header) {
    final data = ByteData.sublistView(
      header,
      userVersionOffset,
      userVersionOffset + 4,
    );
    return data.getUint32(0, Endian.big);
  }
}

/// marker 判定结果。
enum MarkerVerdict {
  /// marker 存在、库的 `user_version` 等于当前 schemaVersion
  /// → 迁移其实已经成功，只是 marker 没删掉（僵尸 marker）→ 删掉它正常启动。
  zombie,

  /// 库版本落后 / 读不出来 → marker 是真失败 → 进降级页。
  genuine,

  /// 库版本**高于**当前 schemaVersion（用户装过更新版本的 App 又装回旧版）
  /// → 绝不能当僵尸删掉：删了就会把版本号写回旧值，数据更难救。
  newerData,
}

/// 判定 marker 是否可信（纯函数，便于单测）。
///
/// [userVersion] 为 `DatabaseFileHealth.readUserVersion` 的结果，
/// null 表示读不出来（当作真失败处理 —— 宁可多给一次「再试一次」的机会，
/// 也不能在库真的坏掉时假装健康）。
MarkerVerdict judgeMarker({
  required int? userVersion,
  required int schemaVersion,
}) {
  if (userVersion == null) return MarkerVerdict.genuine;
  if (userVersion == schemaVersion) return MarkerVerdict.zombie;
  if (userVersion > schemaVersion) return MarkerVerdict.newerData;
  return MarkerVerdict.genuine;
}
