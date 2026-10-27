import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fittrack/core/services/ai_service.dart' show AiService;
import 'package:fittrack/core/services/web_tools_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 联网类只读工具：web_search / fetch_url（自动执行，不需要用户确认）
///
/// 为什么单独一组：这两个工具只调 DeepSeek 的 tools 接口，不碰本地库；
/// 跟查 App 内数据的只读处理器分开放，读代码时不会误以为它们会写库。
///
/// API Key 与 chat 共用：从设置里取，跑 [AiService.resolveKey] 兜底
/// `--dart-define=DEEPSEEK_API_KEY`。没配置时抛 [AiToolException]，不静默失败。
class AiToolWebReaders extends AiToolHandler {
  /// [client] 只给单测注入 MockClient 用，正式运行时传 null 由服务自建
  const AiToolWebReaders(super.repos, {http.Client? client}) : _client = client;

  final http.Client? _client;

  /// 未配置 Key 时的提示（不弹服务端错误，直说缺什么）
  static const noKeyMessage = '还没配置 API Key';

  /// 「联网搜索」开关关闭时的统一拒绝文案（提示去哪里打开）
  static const webDisabledMessage = '联网搜索已关闭';

  @override
  Set<String> get toolNames =>
      const {AiToolSpecs.webSearch, AiToolSpecs.fetchUrl};

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    // 开关关闭时两个工具都拒：即使模型从历史上下文里"记得"这两个工具，
    // 也不能真的发出去（搜索按次计费，用户明确关了就别花这个钱）
    await _ensureWebEnabled();
    switch (call.name) {
      case AiToolSpecs.webSearch:
        final query = AiToolArgs.webSearchQuery(call.arguments);
        return AiToolPreview(
          call: call,
          label: '联网搜索',
          detail: '搜索"$query"',
          needsConfirm: false,
        );
      case AiToolSpecs.fetchUrl:
        // 预览阶段就校验链接：非法链接不弹网络请求，也不进模型上下文
        final uri = AiToolArgs.fetchUrl(call.arguments);
        return AiToolPreview(
          call: call,
          label: '读取网页',
          detail: '读取：${uri.host}',
          needsConfirm: false,
        );
      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    await _ensureWebEnabled();
    switch (call.name) {
      case AiToolSpecs.webSearch:
        return _webSearch(call.arguments);
      case AiToolSpecs.fetchUrl:
        return _fetchUrl(call.arguments);
      default:
        unsupported(call);
    }
  }

  /// 搜索：结果按「≤5 条、摘要 ≤500 字」回传，正文字段一律不带
  Future<String> _webSearch(Map<String, dynamic> args) async {
    final query = AiToolArgs.webSearchQuery(args);
    final count = AiToolArgs.webSearchCount(args);
    try {
      final results = await WebToolsService.search(
        apiKey: await _apiKey(),
        query: query,
        count: count,
        client: _client,
      );
      return jsonEncode({
        'ok': true,
        'query': query,
        'count': results.length,
        'results': [
          for (final r in results)
            {
              'title': r.title,
              'url': r.url,
              'summary': r.summary,
              'site_name': r.siteName,
              'date': r.date,
              'authority': r.authority,
            },
        ],
      });
    } on WebToolsException catch (e) {
      // 交给模型说「没搜到可靠信息」，而不是把整轮对话打断
      return _failureJson(e.message);
    }
  }

  /// 抓正文：Markdown 已截断到 6000 字符，带上原始 url 便于模型标来源
  Future<String> _fetchUrl(Map<String, dynamic> args) async {
    final uri = AiToolArgs.fetchUrl(args);
    final url = uri.toString();
    try {
      final page = await WebToolsService.fetchPage(
        apiKey: await _apiKey(),
        url: url,
        client: _client,
      );
      return jsonEncode({
        'ok': true,
        'title': page.title,
        'content': page.content,
        'url': url,
      });
    } on WebToolsException catch (e) {
      return _failureJson(e.message);
    }
  }

  /// 失败也返回 JSON：提示词里约定了模型见到 ok:false 要直说、不重试
  static String _failureJson(String message) =>
      jsonEncode({'ok': false, 'error': message});

  /// 取生效的 API Key（设置里的优先，编译期注入兜底）
  Future<String> _apiKey() async {
    final settings = await repos.settings.get();
    final key = AiService.resolveKey(settings?.aiApiKey);
    if (key == null) throw const AiToolException(noKeyMessage);
    return key;
  }

  /// 联网开关校验：读设置（没设置过 / 老库一律按开启处理）
  ///
  /// 抛 [AiToolException] 而不是返回 ok:false —— 关闭是「这个能力不存在」，
  /// 让模型看到明确的中文原因，比让它自己猜要稳。
  Future<void> _ensureWebEnabled() async {
    final settings = await repos.settings.get();
    if (settings?.aiWebSearchEnabled ?? true) return;
    throw const AiToolException(webDisabledMessage);
  }
}
