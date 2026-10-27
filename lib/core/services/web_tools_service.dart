import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fittrack/core/services/ai_service.dart' show AiService;

/// 一条联网搜索结果（摘要已裁剪，正文不回传给模型）
class WebSearchResult {
  final String title;
  final String url;

  /// 摘要（服务端 summary 为空时回落 snippet）
  final String summary;

  /// 站点名 / 发布日期（服务端原样返回）/ 权威性（-1~4，-1 = 未知）
  final String? siteName;
  final String? date;
  final int? authority;

  const WebSearchResult({
    required this.title, required this.url, required this.summary,
    this.siteName, this.date, this.authority,
  });
}

/// 一次网页抓取的结果（content 是 Markdown 正文，已截断）
class WebFetchResult {
  final String title;
  final String content;

  const WebFetchResult({required this.title, required this.content});
}

/// DeepSeek 网页搜索 / 网页抓取（只读工具的服务层）
///
/// 与 chat 共用同一把 Bearer Key 和 baseUrl；端点 `POST {base}/v1/tools/search`
/// 与 `POST {base}/v1/tools/fetch`；计费 ¥5 / 1000 次成功请求（见 [priceNote]）。
class WebToolsService {
  WebToolsService._();

  static const _baseUrl = String.fromEnvironment('DEEPSEEK_BASE_URL',
      defaultValue: 'https://api.deepseek.com');

  static const requestTimeout = Duration(seconds: 20); // 单次请求超时

  /// 回传给模型的条数上限 / 单条摘要字数上限 / 正文截断长度
  static const maxResults = 5;
  static const maxSummaryChars = 500;
  static const maxContentChars = 6000;

  static const truncatedMark = '…（内容已截断）';

  static const priceNote = '联网搜索 / 读网页按次计费（¥5 / 1000 次），仅在需要时调用';

  /// 联网搜索：返回 ≤[maxResults] 条结果（失败抛 [WebToolsException]）
  static Future<List<WebSearchResult>> search({
    required String apiKey, required String query,
    int count = maxResults, String? oriQuestion, http.Client? client,
  }) async {
    final json = await _post(
      apiKey: apiKey, path: '/tools/search', body: {
        'query': query,
        'count': count.clamp(1, 50),
        if (oriQuestion != null && oriQuestion.trim().isNotEmpty)
          'ori_question': oriQuestion.trim(),
        // 只要摘要不要正文：正文由 fetch_url 单独抓，避免一次塞满上下文
        'need_content': false,
      },
      client: client,
    );
    return parseSearch(json);
  }

  static Future<WebFetchResult> fetchPage({
    required String apiKey, required String url, http.Client? client,
  }) async {
    final json = await _post(
      apiKey: apiKey, path: '/tools/fetch', body: {'url': url}, client: client);
    return WebFetchResult(
      title: _firstText([json['title']]) ?? '',
      content: clipContent(_firstText([json['content']]) ?? ''),
    );
  }

  /// 解析搜索响应（纯函数，便于单测）
  static List<WebSearchResult> parseSearch(Map<String, dynamic> json) {
    final raw = json['results'];
    if (raw is! List) return const [];
    final out = <WebSearchResult>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      out.add(WebSearchResult(
        title: _firstText([item['title']]) ?? '', url: _firstText([item['url']]) ?? '',
        // summary 为空时回落 snippet：有的站点只返回摘要片段
        summary: clipSummary(_firstText([item['summary'], item['snippet']]) ?? ''),
        siteName: _firstText([item['site_name']]),
        date: _firstText([item['date']]),
        authority: (item['authority'] as num?)?.toInt(),
      ));
      if (out.length >= maxResults) break;
    }
    return out;
  }

  /// 摘要截断（超出加省略号）/ 正文截断（超出加 [truncatedMark]）
  static String clipSummary(String text) =>
      AiService.truncate(text, maxSummaryChars);

  static String clipContent(String content) => content.length <= maxContentChars
      ? content
      : '${content.substring(0, maxContentChars)}$truncatedMark';

  static Future<Map<String, dynamic>> _post({
    required String apiKey, required String path,
    required Map<String, dynamic> body, http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };
      final res = await httpClient
          .post(Uri.parse(_endpoint(path)),
              headers: headers, body: jsonEncode(body))
          .timeout(requestTimeout);
      // 中文必须按 UTF-8 解，否则错误文案会变成乱码
      final text = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode != 200) {
        throw WebToolsException(_httpMessage(res.statusCode, text), body: text);
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const WebToolsException('联网接口返回的数据看不懂，稍后再试');
      }
      return decoded;
    } on WebToolsException {
      rethrow;
    } on TimeoutException {
      throw const WebToolsException('联网请求超时，稍后再试', isNetworkError: true);
    } catch (e) {
      throw WebToolsException(_networkText(e), isNetworkError: true);
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static String _endpoint(String path) {
    final base = _baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return '${base.endsWith('/v1') ? base : '$base/v1'}$path';
  }

  /// HTTP 状态码 → 可读中文提示（并入服务端 error.message，便于自助排查）
  static String _httpMessage(int status, String body) {
    final serverMsg = AiService.extractServerMessage(body);
    final suffix = serverMsg == null
        ? ''
        : '：${AiService.truncate(serverMsg, AiService.serverMessageMaxChars)}';
    final plain = '联网接口出错（$status），稍后再试';
    if (status == 401) return 'API Key 无效或已过期，请重新填写$suffix';
    if (status == 402) return '账户余额不足，请到 DeepSeek 平台充值$suffix';
    if (status == 429) return '联网请求太频繁，稍等几秒再试$suffix';
    if (status >= 500) return 'DeepSeek 联网服务暂时不可用，稍后再试$suffix';
    return serverMsg == null ? plain : '联网接口出错（$status）$suffix';
  }

  /// 网络异常 → 友好文案
  static String _networkText(Object e) {
    final s = e.toString();
    if (s.contains('Failed host lookup') || s.contains('EAI_NODATA')) {
      return '域名解析失败，网络可能有波动，稍后再试';
    }
    return s.contains('SocketException') || s.contains('Connection')
        ? '网络连接中断，检查网络后再试'
        : '联网请求失败，稍后再试';
  }

  static String? _firstText(List<Object?> values) {
    for (final v in values) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

/// 联网工具异常（上层据此展示可读错误）
class WebToolsException implements Exception {
  final String message;
  final String? body;

  /// 网络类错误（可重试）
  final bool isNetworkError;

  const WebToolsException(this.message, {this.body, this.isNetworkError = false});

  @override
  String toString() => message;
}
