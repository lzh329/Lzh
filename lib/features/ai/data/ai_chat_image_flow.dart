import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image_picker/image_picker.dart';

/// 图片消息相关异常（message 直接展示给用户）
class AiImageException implements Exception {
  final String message;

  const AiImageException(this.message);

  @override
  String toString() => message;
}

/// 一条待发送的 user 消息：给模型的 content + 落库用的文本
class AiUserPayload {
  /// 传给模型的 content（纯文本是 String，带图片是 List）
  final Object content;

  /// 落库文本（数据库只存文本，图片用「[图片]」占位）
  final String historyText;

  const AiUserPayload({required this.content, required this.historyText});
}

/// [AiChatImageFlow.buildUserPayload] 的结果：要么成功，要么带一句给用户看的文案
class AiUserPayloadResult {
  final AiUserPayload? payload;
  final String? error;

  const AiUserPayloadResult.ok(AiUserPayload this.payload) : error = null;
  const AiUserPayloadResult.fail(String this.error) : payload = null;

  bool get isOk => payload != null;

  /// 组装一条 user 消息；失败不抛异常，统一转成用户可读文案
  static Future<AiUserPayloadResult> load({
    required String text,
    File? image,
  }) async {
    try {
      return AiUserPayloadResult.ok(
        await AiChatImageFlow.buildUserPayload(text: text, image: image),
      );
    } on AiImageException catch (e) {
      return AiUserPayloadResult.fail(e.message);
    } catch (e) {
      debugPrint('图片处理失败: $e');
      return const AiUserPayloadResult.fail('图片读取失败，换一张试试');
    }
  }
}

/// 聊天图片流程：选图 → 压缩 → base64 → 多模态消息体
///
/// 除 [pick] 以外的成员都是纯逻辑（不依赖插件），便于单测。
class AiChatImageFlow {
  AiChatImageFlow._();

  /// 图片 base64 编码后的字符上限（约 2MB）
  static const int maxBase64Chars = 2 * 1024 * 1024;

  /// 用户只发图片、没写文字时的默认提问
  static const String defaultText = '看看这个';

  /// 历史里代替图片的占位文字（数据库只存文本）
  static const String imagePlaceholder = '[图片]';

  /// 选一张图（拍照 / 相册），用户取消返回 null
  ///
  /// 选图阶段就压到 1280px / 质量 80，尽量避开后面的体积上限。
  static Future<File?> pick({required bool fromCamera}) async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      imageQuality: 80,
    );
    if (picked == null) return null;
    return File(picked.path);
  }

  /// 组装一条 user 消息：纯文本直接用，带图片则生成多模态 content
  ///
  /// 图片超过体积上限时抛 [AiImageException]。
  static Future<AiUserPayload> buildUserPayload({
    required String text,
    File? image,
  }) async {
    final trimmed = text.trim();
    if (image == null) {
      return AiUserPayload(content: trimmed, historyText: trimmed);
    }
    final dataUrl = await toDataUrl(image);
    return AiUserPayload(
      content: buildContent(text: trimmed, dataUrl: dataUrl),
      historyText: historyText(trimmed),
    );
  }

  /// 读取文件 → base64 data URL；超过上限抛 [AiImageException]
  ///
  /// 先按原始字节数判断体积，超限直接抛，避免把几十 MB 的图全量 base64
  /// 编码（编码膨胀 4/3 且会产生一个几乎两倍大的临时字符串）。
  static Future<String> toDataUrl(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const AiImageException('这张图读不出来，换一张试试');
    }
    if (bytes.length > maxBase64Chars * 3 ~/ 4) {
      throw const AiImageException('图片太大，换一张或降低画质');
    }
    final encoded = base64Encode(bytes);
    if (isOversize(encoded)) {
      throw const AiImageException('图片太大，换一张或降低画质');
    }
    return 'data:image/jpeg;base64,$encoded';
  }

  /// base64 文本是否超过体积上限
  static bool isOversize(String base64Text) =>
      base64Text.length > maxBase64Chars;

  /// 构造多模态 user 消息内容（文字 + 图片）
  static List<Map<String, dynamic>> buildContent({
    required String text,
    required String dataUrl,
  }) {
    final trimmed = text.trim();
    return [
      {
        'type': 'text',
        'text': trimmed.isEmpty ? defaultText : trimmed,
      },
      {
        'type': 'image_url',
        'image_url': {'url': dataUrl},
      },
    ];
  }

  /// 落库文本：`<文字> [图片]`，无文字则为 `[图片]`
  static String historyText(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? imagePlaceholder : '$trimmed $imagePlaceholder';
  }
}
