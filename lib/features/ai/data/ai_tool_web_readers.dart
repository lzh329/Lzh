import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:http/http.dart' as http;

import 'package:fittrack/core/services/ai_providers.dart' show aiProviderById;
import 'package:fittrack/features/ai/data/ai_service.dart' show AiService;
import 'package:fittrack/features/ai/data/local_page_fetcher.dart';
import 'package:fittrack/features/ai/data/web_tools_service.dart';
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

  /// 「联网」总开关关闭时的统一拒绝文案（提示去哪里打开）
  static const webDisabledMessage = '联网已关闭';

  /// 当前服务商没有搜索接口时的拒绝文案
  static const searchUnsupportedMessage = '当前 AI 服务商不支持联网搜索';

  @override
  Set<String> get toolNames =>
      const {AiToolSpecs.webSearch, AiToolSpecs.fetchUrl};

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    // 开关关闭时两个工具都拒：即使模型从历史上下文里"记得"这两个工具，
    // 也不能真的发出去（搜索按次计费，用户明确关了就别花这个钱）
    switch (call.name) {
      case AiToolSpecs.webSearch:
        await _ensureSearchEnabled();
        final query = AiToolArgs.webSearchQuery(call.arguments);
        return AiToolPreview(
          call: call,
          label: '联网搜索',
          detail: '搜索"$query"',
          needsConfirm: false,
        );
      case AiToolSpecs.fetchUrl:
        await _ensureFetchEnabled();
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
    switch (call.name) {
      case AiToolSpecs.webSearch:
        await _ensureSearchEnabled();
        return _webSearch(call.arguments);
      case AiToolSpecs.fetchUrl:
        await _ensureFetchEnabled();
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

  /// 抓正文：截断到 6000 字符，带上原始 url 便于模型标来源。
  ///
  /// 两条通道：
  /// 1. **DeepSeek** → 服务端 `/v1/tools/fetch`（正文已经是干净的 Markdown）；
  /// 2. **任何服务商**（含 DeepSeek 调用失败时）→ [LocalPageFetcher] 本地抓取。
  ///
  /// 为什么要兜底而不是直接报错：DeepSeek 端点挂了 / 没配 key / 用户换了服务商，
  /// 都不该让"帮我看看这个链接"变成一句"打不开"。本地抓到的内容差一些
  /// （只有标题+简介+HTML 文字），但**能用**。
  Future<String> _fetchUrl(Map<String, dynamic> args) async {
    final uri = AiToolArgs.fetchUrl(args);
    final url = uri.toString();
    final settings = await repos.settings.get();
    final provider = aiProviderById(settings?.aiProviderId);

    if (provider.id == 'deepseek') {
      try {
        final page = await WebToolsService.fetchPage(
          apiKey: await _apiKey(),
          url: url,
          client: _client,
        );
        // 服务端也可能只拿到空壳（抖音这类）：**正文为空**就继续走本地通道，
        // 本地通道会用移动 UA + 分享页再试一次。
        // 只判"空"不判"短"：服务端返回的短正文是合法的（短文/公告），
        // 拿长度当判据会把正常内容也丢给本地重抓。
        if (page.content.trim().isNotEmpty) {
          return _pageJson(page.title, page.content, url, 'deepseek');
        }
      } on AiToolException {
        // 没配 key：读网页不需要 key，继续走本地抓取（web_search 才需要）
      } on WebToolsException catch (e) {
        debugPrint('DeepSeek 抓取失败，改用本地抓取：${e.message}');
      }
    }

    try {
      final page = await LocalPageFetcher.fetch(url, client: _client);
      // 请求成功但内容拿不到（SPA 空壳）⇒ **不能**回 ok:true + 空正文，
      // 否则模型会以为读到了、然后按标题编动作
      if (page.contentUnavailable) return _unavailableJson(url);
      return _pageJson(page.title, page.content, url, 'local');
    } on WebToolsException catch (e) {
      return _failureJson(e.message);
    }
  }

  /// "读到了请求但没读到正文"（抖音/小红书）—— 文案要能让模型如实转述
  static String _unavailableJson(String url) => jsonEncode({
        'ok': false,
        'error': LocalPage.unavailableMessage,
        'url': url,
      });

  /// 统一的成功回执；`source` 便于排查"这条内容是服务端抓的还是本地抓的"
  static String _pageJson(
          String title, String content, String url, String source) =>
      jsonEncode({
        'ok': true,
        'title': title,
        'content': content,
        'url': url,
        'source': source,
      });

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

  /// 读网页的开关校验：**只看用户的总开关**（本地抓取不花钱、不依赖服务商）
  ///
  /// 抛 [AiToolException] 而不是返回 ok:false —— 关闭是「这个能力不存在」，
  /// 让模型看到明确的中文原因，比让它自己猜要稳。
  Future<void> _ensureFetchEnabled() async {
    final settings = await repos.settings.get();
    if (settings?.aiWebSearchEnabled ?? true) return;
    throw const AiToolException(webDisabledMessage);
  }

  /// 搜索的开关校验：总开关 + **服务商必须是 DeepSeek**（搜索只有它有接口）
  Future<void> _ensureSearchEnabled() async {
    final settings = await repos.settings.get();
    if (!(settings?.aiWebSearchEnabled ?? true)) {
      throw const AiToolException(webDisabledMessage);
    }
    final provider = aiProviderById(settings?.aiProviderId);
    if (provider.id != 'deepseek') {
      throw const AiToolException(searchUnsupportedMessage);
    }
  }
}
