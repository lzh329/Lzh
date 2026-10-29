import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

/// 让嘎教练点评对比照时预填的问题
///
/// 为什么预填而不是自动发送：图像请求要花钱，而且用户可能想换个问法。
/// 替他做这个决定，等于替他花钱。
const String compareReviewPrompt = '帮我对比这两张体态照片，说说变化和接下来该注意什么';

/// 把并排对比区域截成一张 PNG 临时文件
///
/// 设计原因：DeepSeek 视觉**一次只能吃一张图**，而对比页本来就是两张并排。
/// 分两次发两张图既贵又割裂（模型看不到"并排"这个信息本身），
/// 所以把用户眼前看到的这块画面截成一张，模型看到的就是用户看到的。
///
/// [dir] / [now] 供单测注入；生产走临时目录。
Future<File> writeCompareSnapshot(
  Uint8List png, {
  Directory? dir,
  DateTime? now,
}) async {
  final target = dir ?? await Directory.systemTemp.createTemp('fittrack_cmp');
  if (!await target.exists()) await target.create(recursive: true);
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final file = File(p.join(target.path, 'fittrack_compare_$stamp.png'));
  await file.writeAsBytes(png, flush: true);
  await _cleanupOldSnapshots(target, keep: file);
  return file;
}

/// 只留最新一张：这些临时图没有任何复用价值，攒着只会占空间
Future<void> _cleanupOldSnapshots(Directory dir, {required File keep}) async {
  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('fittrack_compare_')) continue;
      if (entity.path == keep.path) continue;
      try {
        await entity.delete();
      } catch (_) {}
    }
  } catch (_) {
    // 清理失败不影响功能
  }
}

/// 解析外部带进来的初始图片路径（**纯函数**，便于单测）
///
/// 路径为空 / 文件不存在 → null。不回退到"用路径字符串硬造一个 File"：
/// 文件被系统清理后 `Image.file` 会抛错，那种崩溃发生在用户点发送之后。
File? resolveInitialImage(
  String? path, {
  bool Function(String path)? exists,
}) {
  if (path == null || path.isEmpty) return null;
  final check = exists ?? (p) => File(p).existsSync();
  return check(path) ? File(path) : null;
}

/// 把 [RepaintBoundary] 渲染成 PNG 字节；失败返回 null（调用方给提示，别静默跳转）
Future<Uint8List?> captureBoundaryPng(GlobalKey key) async {
  try {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return null;
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}
