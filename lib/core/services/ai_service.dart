import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 聊天消息（OpenAI 兼容格式）
class AiMessage {
  final String role; // system / user / assistant
  final String content;

  const AiMessage({required this.role, required this.content});
}

/// DeepSeek 聊天服务（OpenAI 兼容）
///
/// - 端点：https://api.deepseek.com/chat/completions
/// - 默认模型 deepseek-flash（即 DeepSeek-V4.1-Flash，支持流式 + 视觉）
/// - SSE 流式解析：每收到一段增量回调 [onDelta]
/// - API Key 解析：--dart-define 优先，设置里存的 key 兜底
class AiService {
  AiService._();

  static const _endpoint = 'https://api.deepseek.com/chat/completions';
  static const _model =
      String.fromEnvironment('DEEPSEEK_MODEL', defaultValue: 'deepseek-flash');
  static const _envKey = String.fromEnvironment('DEEPSEEK_API_KEY');

  /// 解析最终生效的 API Key（编译期注入优先）
  static String? resolveKey(String? settingsKey) {
    if (_envKey.isNotEmpty) return _envKey;
    if (settingsKey != null && settingsKey.trim().isNotEmpty) {
      return settingsKey.trim();
    }
    return null;
  }

  /// 流式对话：返回完整回复文本（同时通过 [onDelta] 逐段回调）
  static Future<String> streamChat({
    required String apiKey,
    required List<AiMessage> messages,
    required void Function(String delta) onDelta,
    double temperature = 0.8,
    int maxTokens = 2048,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final req = http.Request('POST', Uri.parse(_endpoint))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': _model,
          'messages': messages
              .map((m) => {'role': m.role, 'content': m.content})
              .toList(),
          'stream': true,
          'temperature': temperature,
          'max_tokens': maxTokens,
        });

      final res = await httpClient.send(req);
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw AiServiceException(
          '接口返回 ${res.statusCode}', body: body,
        );
      }

      final buffer = StringBuffer();
      var done = false;
      await for (final chunk in res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (isDoneLine(chunk)) {
          done = true;
          break;
        }
        final delta = parseSseLine(chunk);
        if (delta == null || delta.isEmpty) continue;
        buffer.write(delta);
        onDelta(delta);
      }
      final text = buffer.toString();
      if (text.isEmpty && !done) {
        throw const AiServiceException('模型没有返回内容，请稍后再试');
      }
      return text;
    } on AiServiceException {
      rethrow;
    } catch (e) {
      throw AiServiceException('网络请求失败：$e');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// 该行是否为 SSE 结束标记（data: [DONE]）
  static bool isDoneLine(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith('data:') &&
        trimmed.substring(5).trim() == '[DONE]';
  }

  /// 解析单行 SSE data，返回增量文本
  /// - 返回 null：不是 data 行 / 结束行，跳过
  /// - 返回 ''：是 data 行但没有 content 字段（如首尾帧、心跳帧）
  static String? parseSseLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return null;
    final data = trimmed.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return '';
      final delta = choices.first['delta'] as Map<String, dynamic>?;
      return (delta?['content'] as String?) ?? '';
    } catch (_) {
      // 心跳帧 / 异常帧，忽略
      return '';
    }
  }
}

/// AI 服务统一异常（上层据此展示可读错误）
class AiServiceException implements Exception {
  final String message;
  final String? body;
  const AiServiceException(this.message, {this.body});

  @override
  String toString() => message;
}
