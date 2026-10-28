import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// `db_replaced` 标记 —— 语义是「**可能**换过库，打开后重建」，不是「已经换过」。
///
/// 为什么需要它：恢复流程的最后一步是 `rename` 覆盖库文件。如果进程正好在
/// rename 之后、新库打开之前被杀掉，内存里还握着旧库的句柄/缓存 —— 下一次
/// 启动必须知道"库可能已经换了"，强制重建连接。
///
/// 写入顺序（不可颠倒）：**先写标记（fsync）→ 再 rename 库文件**。
/// 反过来的话，rename 之后到写标记之间有一段时间没有任何东西阻止同进程
/// 继续用旧句柄写，代价是静默丢数据。
///
/// 清除时机：**新库打开成功之后**，不是 rename 成功之后 —— 标记的语义就是
/// "还没确认新库可用"。
class DbReplacedMarker {
  static const String fileName = 'db_replaced.json';

  /// 标记文件路径（`baseDir` 仅供单测注入）
  static Future<File> markerFile({Directory? baseDir}) async {
    final dir = baseDir ?? await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  /// 标记是否存在 —— **封存判定的唯一依据**（不解析内容，避免"文件坏了就当我没封存"）
  static Future<bool> exists({Directory? baseDir}) async {
    try {
      return await (await markerFile(baseDir: baseDir)).exists();
    } catch (_) {
      return false;
    }
  }

  /// 写标记。`flush: true` 是硬要求：掉电等于没写就没有任何意义。
  static Future<void> write({
    String? preRestore,
    String? failingStep,
    Directory? baseDir,
  }) async {
    final file = await markerFile(baseDir: baseDir);
    final payload = jsonEncode(<String, dynamic>{
      'at': DateTime.now().toIso8601String(),
      if (preRestore != null) 'preRestore': preRestore,
      if (failingStep != null) 'failingStep': failingStep,
    });
    // 原子写：先 .tmp 再 rename，避免半截 JSON 让标记自己成为故障源
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    await temp.rename(file.path);
  }

  /// 清除标记（新库打开成功后调用）。清不掉不影响正确性 —— 下次启动会自然重试。
  static Future<void> clear({Directory? baseDir}) async {
    try {
      final file = await markerFile(baseDir: baseDir);
      if (await file.exists()) await file.delete();
      final temp = File('${file.path}.tmp');
      if (await temp.exists()) await temp.delete();
    } catch (_) {
      // 忽略
    }
  }
}

/// 封存态：库文件已经被替换，当前进程里的连接不可再信任。
///
/// 封存后 `databaseProvider` 直接抛 [message]，UI 进全屏封存页（不可返回）。
/// 这不是"出错了"，而是"必须重启才能继续"——所以它不能重试、不能绕过。
class DatabaseSeal {
  DatabaseSeal._();

  /// 展示给用户的固定文案（UI 与异常共用，避免两处不一致）
  static const String message = '数据库已被替换，请重启';

  static bool _sealed = false;

  static bool get sealed => _sealed;

  static void seal() => _sealed = true;

  static void unseal() => _sealed = false;

  /// 单测用：重置进程级状态
  @visibleForTesting
  static void reset() => _sealed = false;
}
