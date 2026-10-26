import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 聊天消息（OpenAI 兼容格式，支持工具调用）
class AiMessage {
  final String role; // system / user / assistant / tool
  final String content;

  /// assistant 请求的工具调用（仅 role=assistant 时使用）
  final List<AiToolCall>? toolCalls;

  /// tool 消息回传时的调用 id（仅 role=tool 时使用）
  final String? toolCallId;

  const AiMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role, 'content': content};
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!
          .map((c) => {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': c.argumentsJson},
              })
          .toList();
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId!;
    return map;
  }
}

/// 一轮流式结果：正文 + 模型请求的工具调用
class AiStreamResult {
  final String content;
  final List<AiToolCall> toolCalls;
  const AiStreamResult({required this.content, this.toolCalls = const []});
}

/// DeepSeek 聊天服务（OpenAI 兼容）
///
/// - 端点：https://api.deepseek.com/chat/completions（可用 --dart-define=DEEPSEEK_BASE_URL 覆盖）
/// - 默认模型 deepseek-flash（即 DeepSeek-V4.1-Flash，支持流式 + 视觉）
/// - SSE 流式解析：每收到一段增量回调 [onDelta]
/// - API Key 解析：--dart-define 优先，设置里存的 key 兜底
/// - 网络瞬断（如 DNS 临时失败）自动重试一次
class AiService {
  AiService._();

  static const _baseUrl = String.fromEnvironment('DEEPSEEK_BASE_URL',
      defaultValue: 'https://api.deepseek.com');
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

  /// 流式对话：返回正文与工具调用（同时通过 [onDelta] 逐段回调正文）
  static Future<AiStreamResult> streamChat({
    required String apiKey,
    required List<AiMessage> messages,
    required void Function(String delta) onDelta,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.8,
    int maxTokens = 2048,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      return await _sendOnce(
        httpClient: httpClient,
        apiKey: apiKey,
        messages: messages,
        onDelta: onDelta,
        tools: tools,
        temperature: temperature,
        maxTokens: maxTokens,
      );
    } on AiServiceException catch (e) {
      // 只对网络类错误重试一次（鉴权 / 余额 / 限流重试没有意义）
      if (!e.isNetworkError) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        return await _sendOnce(
          httpClient: httpClient,
          apiKey: apiKey,
          messages: messages,
          onDelta: onDelta,
          tools: tools,
          temperature: temperature,
          maxTokens: maxTokens,
        );
      } on AiServiceException catch (retryError) {
        throw retryError.isNetworkError
            ? const AiServiceException('网络连接不上，检查手机网络后点重试',
                isNetworkError: true)
            : retryError;
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Future<AiStreamResult> _sendOnce({
    required http.Client httpClient,
    required String apiKey,
    required List<AiMessage> messages,
    required void Function(String delta) onDelta,
    required List<Map<String, dynamic>>? tools,
    required double temperature,
    required int maxTokens,
  }) async {
    try {
      final body = <String, dynamic>{
        'model': _model,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
        'temperature': temperature,
        'max_tokens': maxTokens,
      };
      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }

      final req = http.Request('POST', Uri.parse('$_baseUrl/chat/completions'))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);

      final res = await httpClient.send(req);
      if (res.statusCode != 200) {
        final errBody = await res.stream.bytesToString();
        throw AiServiceException(
          _httpErrorMessage(res.statusCode, errBody),
          body: errBody,
        );
      }

      final buffer = StringBuffer();
      final toolAcc = <int, _ToolAcc>{};
      var done = false;
      await for (final chunk in res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (isDoneLine(chunk)) {
          done = true;
          break;
        }
        final delta = parseSseLine(chunk);
        if (delta != null && delta.isNotEmpty) {
          buffer.write(delta);
          onDelta(delta);
        }
        final tc = parseToolCallDelta(chunk);
        if (tc != null) {
          final acc = toolAcc.putIfAbsent(tc.index, () => _ToolAcc());
          if (tc.id != null && tc.id!.isNotEmpty) acc.id = tc.id!;
          if (tc.name != null && tc.name!.isNotEmpty) acc.name = tc.name!;
          if (tc.arguments != null) acc.arguments.write(tc.arguments);
        }
      }
      final text = buffer.toString();
      final calls = toolAcc.entries
          .where((e) => e.value.name != null)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final toolCalls = [
        for (final e in calls)
          AiToolCall(
            id: e.value.id ?? 'call_${e.key}',
            name: e.value.name!,
            argumentsJson: e.value.arguments.toString(),
          ),
      ];
      if (text.isEmpty && !done && toolCalls.isEmpty) {
        throw const AiServiceException('模型没有返回内容，稍后再试');
      }
      return AiStreamResult(content: text, toolCalls: toolCalls);
    } on AiServiceException {
      rethrow;
    } catch (e) {
      // SocketException / ClientException / DNS 失败等统一转成友好文案
      throw AiServiceException(_networkErrorText(e), isNetworkError: true);
    }
  }

  /// HTTP 状态码 → 可读中文提示（优先取服务端 error.message）
  static String _httpErrorMessage(int status, String body) {
    String? serverMsg;
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map && err['message'] is String) {
        serverMsg = err['message'] as String;
      }
    } catch (_) {}
    switch (status) {
      case 401:
        return 'API Key 无效或已过期，请重新填写';
      case 402:
        return '账户余额不足，请到 DeepSeek 平台充值';
      case 429:
        return '请求太频繁，稍等几秒再试';
      case 500:
      case 502:
      case 503:
        return 'DeepSeek 服务暂时不可用，稍后再试';
      default:
        return serverMsg != null && serverMsg.length < 120
            ? 'AI 接口出错：$serverMsg'
            : 'AI 接口出错（$status），稍后再试';
    }
  }

  /// 网络异常 → 友好文案
  static String _networkErrorText(Object e) {
    final s = e.toString();
    if (s.contains('Failed host lookup') || s.contains('EAI_NODATA')) {
      return '域名解析失败，手机网络可能有波动，点重试';
    }
    if (s.contains('SocketException') || s.contains('Connection')) {
      return '网络连接中断，检查网络后点重试';
    }
    if (s.contains('TimeoutException')) {
      return '请求超时，网络较慢，点重试';
    }
    return '网络请求失败，点重试';
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

  /// 解析单行 SSE 中的工具调用增量（流式分片拼接）
  static ToolCallDelta? parseToolCallDelta(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return null;
    final data = trimmed.substring(5).trim();
    if (data.isEmpty || data == '[DONE]') return null;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final delta = choices.first['delta'] as Map<String, dynamic>?;
      final calls = delta?['tool_calls'] as List<dynamic>?;
      if (calls == null || calls.isEmpty) return null;
      final tc = calls.first as Map<String, dynamic>;
      final fn = tc['function'] as Map<String, dynamic>?;
      return ToolCallDelta(
        index: (tc['index'] as num?)?.toInt() ?? 0,
        id: tc['id'] as String?,
        name: fn?['name'] as String?,
        arguments: fn?['arguments'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 流式工具调用增量
class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? arguments;

  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.arguments,
  });
}

class _ToolAcc {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

/// AI 服务统一异常（上层据此展示可读错误）
class AiServiceException implements Exception {
  final String message;
  final String? body;

  /// 是否为网络类错误（可重试）
  final bool isNetworkError;
  const AiServiceException(this.message, {this.body, this.isNetworkError = false});

  @override
  String toString() => message;
}
