import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 聊天消息（OpenAI 兼容格式，支持工具调用与多模态内容）
///
/// [content] 有两种形态：
/// - `String`：纯文本（system / 历史消息 / tool 结果都用这种）
/// - `List`：多模态内容，如
///   `[{type:'text', text:'...'}, {type:'image_url', image_url:{url:'data:image/jpeg;base64,...'}}]`
class AiMessage {
  final String role; // system / user / assistant / tool
  final Object content;

  /// assistant 请求的工具调用（仅 role=assistant 时使用）
  final List<AiToolCall>? toolCalls;

  /// tool 消息回传时的调用 id（仅 role=tool 时使用）
  final String? toolCallId;

  /// tool 消息回传时的工具名（DeepSeek 要求 tool 消息带 name）
  final String? toolName;

  const AiMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
  });

  /// 是否携带工具调用
  bool get hasToolCalls => toolCalls != null && toolCalls!.isNotEmpty;

  /// 纯文本视图：多模态消息取其中所有 text 段拼接
  ///
  /// 气泡展示、复制、历史落库都用这个，保证图片消息也有可读文字。
  String get textOnly {
    final value = content;
    if (value is String) return value;
    if (value is List) {
      final buf = StringBuffer();
      for (final part in value) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          buf.write(part['text'] as String);
        }
      }
      return buf.toString();
    }
    return value.toString();
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role};
    // DeepSeek / OpenAI 规定：带 tool_calls 的 assistant 消息 content 必须为 null，
    // 传空字符串会被判 400，故这里显式置 null。
    if (hasToolCalls && textOnly.trim().isEmpty) {
      map['content'] = null;
    } else {
      map['content'] = content;
    }
    if (hasToolCalls) {
      map['tool_calls'] = toolCalls!
          .map((c) => {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': c.argumentsJson},
              })
          .toList();
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId!;
    if (toolName != null && toolName!.isNotEmpty) map['name'] = toolName!;
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
/// - thinking 模式固定关闭（见 [AiService.disabledThinking]），否则工具回合必 400
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

  /// 默认温度：偏高一点让语气更活（用户可在「教练设定」里调，范围 0.3~1.0）
  static const double defaultTemperature = 0.9;

  /// 关闭 DeepSeek V4 的 thinking 模式（请求体顶层的 `thinking` 字段）
  ///
  /// 为什么必须关：
  /// thinking 模式下，**只要请求带 tools**，后续每一次请求都必须把上一轮
  /// assistant 消息的 `reasoning_content` 原样回传，哪怕那一轮并没有真的发起
  /// 工具调用（官方文档原文："for requests carrying the tools parameter, the
  /// reasoning_content must be fully passed back to the API in all subsequent
  /// requests — even for turns where the model did not perform a tool call. If
  /// your code does not correctly pass back reasoning_content, the API will
  /// return a 400 error"）。
  ///
  /// 我们的消息模型与数据库都不存 `reasoning_content`，所以一旦走进工具回合
  /// （第一轮正常、第二轮带 tool 结果）就会稳定 400。聊天教练场景并不需要思维链，
  /// 直接关掉 thinking 最省事：工具调用照常可用，延迟更低、成本更小。
  ///
  /// ⚠️ 不要把这一行删掉 / 改成 enabled —— 删了 400 会立刻回来。
  /// 若以后真要保留 thinking，必须同时做到：
  /// ① 流式解析累加 `choices[0].delta.reasoning_content`；
  /// ② 存到 AiMessage 并在后续请求里对该 assistant 消息输出 `reasoning_content`；
  /// ③ 历史落库一并持久化（需要给 ai_chat_messages 加列）。
  static const Map<String, Object?> disabledThinking = {'type': 'disabled'};

  /// 服务端错误文案最多展示的字数（整段英文塞满 SnackBar 没法读）
  static const int serverMessageMaxChars = 60;

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
    double temperature = defaultTemperature,
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
        // 关掉 thinking：它要求每次请求都回传 reasoning_content，否则工具回合 400
        // （详细说明见 [AiService.disabledThinking]）
        'thinking': disabledThinking,
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
        // 完整响应体打进日志，400 这类问题只能靠它定位
        debugPrint('AI 接口返回 ${res.statusCode}，响应体：$errBody');
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

  /// HTTP 状态码 → 可读中文提示（一律并入服务端 error.message，便于自助排查）
  static String _httpErrorMessage(int status, String body) {
    final serverMsg = extractServerMessage(body);
    final suffix = serverMsg == null
        ? ''
        : '：${truncate(serverMsg, serverMessageMaxChars)}';
    switch (status) {
      case 401:
        return 'API Key 无效或已过期，请重新填写$suffix';
      case 402:
        return '账户余额不足，请到 DeepSeek 平台充值$suffix';
      case 429:
        return '请求太频繁，稍等几秒再试$suffix';
      case 500:
      case 502:
      case 503:
        return 'DeepSeek 服务暂时不可用，稍后再试$suffix';
      default:
        return serverMsg == null
            ? 'AI 接口出错（$status），稍后再试'
            : 'AI 接口出错（$status）$suffix';
    }
  }

  /// 从错误响应体里取服务端 error.message（取不到返回 null）
  static String? extractServerMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final err = json['error'];
        if (err is Map && err['message'] is String) {
          final msg = (err['message'] as String).trim();
          if (msg.isNotEmpty) return msg;
        }
        // 少数网关直接返回 {"message": "..."}
        if (json['message'] is String) {
          final msg = (json['message'] as String).trim();
          if (msg.isNotEmpty) return msg;
        }
      }
    } catch (_) {
      // 非 JSON 错误体：忽略
    }
    return null;
  }

  /// 超出 [max] 个字符时截断并加省略号
  static String truncate(String text, int max) {
    if (max <= 0 || text.length <= max) return text;
    return '${text.substring(0, max)}…';
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
