import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 把用户选的头像**拷贝到应用私有目录**，并删掉上一张
///
/// 为什么必须拷贝：`image_picker` 给的是系统相册里的路径，相册文件随时会被
/// 用户或系统清理 —— 直接存那个路径，过几天头像就变成破图。私有目录
/// （`<appDocuments>/avatar/`）只有我们自己会动。
///
/// [docsDir] / [now] / [exists] 供单测注入（不碰 path_provider 通道）。
/// 返回新头像的绝对路径；拷贝失败返回 null（调用方提示用户，别静默）。
Future<String?> copyAvatarToPrivate(
  String sourcePath, {
  Directory? docsDir,
  DateTime? now,
  String? previousPath,
}) async {
  try {
    final src = File(sourcePath);
    if (!await src.exists()) return null;

    final docs = docsDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'avatar'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final ext =
        p.extension(sourcePath).isEmpty ? '.jpg' : p.extension(sourcePath);
    final dest = File(p.join(dir.path, 'avatar_$stamp$ext'));
    await src.copy(dest.path);

    // 删旧文件：不删的话每次换头像都会留一份，越攒越多且没人再引用
    await deleteAvatarIfUnused(previousPath, keepPath: dest.path);
    return dest.path;
  } catch (_) {
    return null;
  }
}

/// 删掉上一张头像（只删私有目录里的，且不能删到新的这张）
///
/// 单独抽出来是因为"删旧文件"这条最容易漏：换十次头像留十个文件，
/// 一年后就是几十 MB 的垃圾，而这个函数可以单测。
Future<void> deleteAvatarIfUnused(
  String? previousPath, {
  required String keepPath,
  Directory? docsDir,
}) async {
  if (previousPath == null || previousPath.isEmpty) return;
  if (p.equals(previousPath, keepPath)) return;
  try {
    final file = File(previousPath);
    if (!await file.exists()) return;
    // 只删 avatar 目录下的，别的地方的文件一概不动（防止误删用户相册原图）
    if (!p.split(previousPath).contains('avatar')) return;
    await file.delete();
  } catch (_) {
    // 删不掉不影响功能
  }
}
