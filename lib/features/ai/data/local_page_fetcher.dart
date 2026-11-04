import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:fittrack/features/ai/data/douyin_resolver.dart';
import 'package:fittrack/features/ai/data/web_tools_service.dart'
    show WebToolsException, WebToolsService;

/// 本地抓取到的一页：标题 + 可读正文（已剔除标签，已截断）
class LocalPage {
  final String title;
  final String content;

  /// **读不到正文**：页面是 SPA 空壳 / 只有站点名 / 正文太短
  ///
  /// 为什么要这个标记：抖音、小红书这类页面请求会成功（HTTP 200），但内容
  /// 全靠前端渲染。返回 `ok:true + 空正文` 会让模型以为"读到了"，然后按标题
  /// 编动作 —— 比"读不到"严重得多。
  final bool contentUnavailable;

  const LocalPage({
    required this.title,
    required this.content,
    this.contentUnavailable = false,
  });

  /// 读不到正文时的统一回执文案（对用户可读，也明确告诉模型别编）
  static const unavailableMessage = '这个平台（抖音/小红书等）的页面是动态加载的，我读不到视频正文';
}

/// 本地网页抓取 —— `fetch_url` 的**兜底通道**。
///
/// 为什么需要它：DeepSeek 的 `/v1/tools/fetch` 只有 DeepSeek 有；而"帮我看下这个
/// 链接"是通用能力，用户换任何服务商都该能用。所以这里用 `http` 直接取页面、
/// 正则抽标题/简介/正文 —— **不引入新依赖、不花钱、不依赖服务商**。
///
/// 能力边界（要如实告诉模型，别让它以为真看了视频）：
/// - 只拿得到 HTML 里的文字：标题、`meta description`、`og:description`、正文；
/// - 视频页（抖音 / B 站 / YouTube）正文基本是空壳 → 用 [LocalPage.contentUnavailable]
///   明确标出来，而不是假装读到了；
/// - 抓不到 JS 渲染出来的内容（没有浏览器内核）。
class LocalPageFetcher {
  LocalPageFetcher._();

  /// 与 [WebToolsService.maxContentChars] 同口径：6000 字符，超出加截断标记
  static const maxContentChars = WebToolsService.maxContentChars;

  /// 移动 UA：抖音短链在**桌面 UA** 下会落到 SPA 空壳，移动 UA 才会落到
  /// `iesdouyin.com/share/video/{id}` 分享页（带 og 信息）。B 站/公众号同样
  /// 对移动 UA 更友好（不会弹"请用 App 打开"的中间页）。
  static const userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  static const _headers = {
    'User-Agent': userAgent,
    'Accept-Language': 'zh-CN,zh;q=0.9',
    'Accept': 'text/html,application/xhtml+xml',
  };

  /// 跟随跳转的最大次数（短链一般 1~2 跳，5 次足够且能防重定向环）
  static const maxRedirects = 5;

  /// 抓取一个页面。失败一律抛 [WebToolsException]（文案面向用户，可读）
  ///
  /// [client] 只给单测注入 MockClient 用；正式运行传 null，由本方法自建并关闭。
  static Future<LocalPage> fetch(
    String url, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw const WebToolsException('只支持 http / https 链接');
    }

    final httpClient = client ?? http.Client();
    try {
      if (DouyinResolver.isDouyinHost(uri)) {
        return await _fetchDouyin(httpClient, uri, timeout);
      }
      final page = await _getRaw(httpClient, uri, timeout);
      return _pageFrom(page.html);
    } on WebToolsException {
      rethrow;
    } on TimeoutException {
      throw const WebToolsException('这个页面打开太慢（超时），稍后再试');
    } on http.ClientException {
      throw const WebToolsException('打不开这个链接（域名解析或网络问题）');
    } catch (e) {
      // 兜底：任何解析/编码异常都不许把整轮对话打断
      throw WebToolsException('读取这个链接时出错了（$e）');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// 抖音：短链 → 最终 URL 提 video id → 分享页取 og 信息
  ///
  /// 三步都失败时**不抛错**，返回 `contentUnavailable`：请求是成功的，
  /// 只是内容拿不到 —— 让上层给用户一句"读不到正文"，而不是"链接打不开"。
  static Future<LocalPage> _fetchDouyin(
    http.Client client,
    Uri start,
    Duration timeout,
  ) async {
    final landed = await _getRaw(client, start, timeout);

    // 短链自己带了 id 就省一次请求；否则从跳转后的最终 URL 里提
    final id =
        DouyinResolver.videoIdOf(start) ?? DouyinResolver.videoIdOf(landed.url);

    if (id != null) {
      final share = await _getRaw(
          client, Uri.parse(DouyinResolver.shareUrl(id)), timeout);
      final fromShare = _pageFrom(share.html);
      if (!fromShare.contentUnavailable) return fromShare;
    }
    // 兜底：用短链落地页（通常是 SPA 空壳 ⇒ 会被标成读不到正文）
    return _pageFrom(landed.html);
  }

  /// 手动跟跳转：`http` 的 `Response` 不带"最终 URL"，而抖音的 video id
  /// 只在跳转后的 URL 里。所以自己读 `Location` 并逐跳跟随（也便于 MockClient 测）。
  static Future<_RawPage> _getRaw(
      http.Client client, Uri uri, Duration timeout) async {
    var current = uri;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request('GET', current)
        ..headers.addAll(_headers)
        ..followRedirects = false;
      final res = await http.Response.fromStream(
          await client.send(request).timeout(timeout));
      final location = _header(res, 'location');
      if (res.statusCode >= 300 &&
          res.statusCode < 400 &&
          location != null &&
          location.isNotEmpty) {
        current = current.resolve(location);
        continue;
      }
      if (res.statusCode != 200) {
        throw WebToolsException(_statusMessage(res.statusCode));
      }
      return _RawPage(
        url: current,
        // 中文站点普遍是 UTF-8；个别老站不是，allowMalformed 保证不因坏字节崩
        html: utf8.decode(res.bodyBytes, allowMalformed: true),
      );
    }
    throw const WebToolsException('这个链接跳转次数太多，打不开');
  }

  /// 大小写无关地取响应头（`http` 的 headers 在不同实现里大小写不一定一致）
  static String? _header(http.Response res, String name) {
    for (final entry in res.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  static String _statusMessage(int code) => switch (code) {
        401 || 403 => '这个页面需要登录或拒绝访问（HTTP $code）',
        404 => '这个页面不存在（HTTP 404）',
        _ => '这个页面打不开（HTTP $code）',
      };

  /// HTML → [LocalPage]（含"读不到正文"的判定）
  static LocalPage _pageFrom(String html) {
    final title = _titleOf(html);
    final content = _contentOf(html);
    // 判定"没拿到真内容"：
    // ① 正文太短（<30）→ 一定是壳；
    // ② 标题只是站点名 **且** 正文也不够长（<200）→ 壳。
    // 反过来：标题泛但正文丰富（200+）就放过 —— 避免「抖音健身达人」这类
    // 真标题（去掉"抖音"只剩 4 字）被误杀成"读不到"。
    final compact = content.replaceAll(RegExp(r'\s'), '');
    final unavailable = compact.length < 30 ||
        (DouyinResolver.isGenericTitle(title) && compact.length < 200);
    return LocalPage(
      title: title,
      content: content,
      contentUnavailable: unavailable,
    );
  }

  /// `<title>…</title>`
  static String _titleOf(String html) {
    final m = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
        .firstMatch(html);
    return m == null ? '' : _collapse(_decodeEntities(m.group(1) ?? ''));
  }

  /// 正文 = og/description 简介（如果有）+ 去标签后的可读文字，截断到 6000
  static String _contentOf(String html) {
    final description = _descriptionOf(html);
    final body = _visibleText(html);
    final parts = <String>[
      if (description != null && description.isNotEmpty) '简介：$description',
      if (body.isNotEmpty) body,
    ];
    return WebToolsService.clipContent(parts.join('\n\n').trim());
  }

  /// 简介：先 `meta[name=description]`，再 `meta[property=og:description]`，
  /// 再 `meta[property=og:title]`（抖音分享页只有 og 系列）
  static String? _descriptionOf(String html) {
    final metas = _metaAttributes(html);
    for (final key in const [
      'description',
      'og:description',
      'og:title',
      'twitter:description',
    ]) {
      final v = metas[key];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// 把所有 `<meta …>` 的 `(name|property) → content` 收成一张表。
  ///
  /// 直接写两条正则（`name="description" content="…"`）不够 —— 属性顺序可能是
  /// `content` 在前、`name` 在后，两种都得认。所以先把每个 meta 标签的属性
  /// 解析成 map，再查键。
  static Map<String, String> _metaAttributes(String html) {
    final out = <String, String>{};
    final tagRe = RegExp(r'<meta\b[^>]*>', caseSensitive: false);
    final attrRe = RegExp(r'''([a-zA-Z:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    for (final tag in tagRe.allMatches(html)) {
      final attrs = <String, String>{};
      for (final a in attrRe.allMatches(tag.group(0) ?? '')) {
        attrs[(a.group(1) ?? '').toLowerCase()] =
            _decodeEntities(a.group(2) ?? a.group(3) ?? '');
      }
      final key = attrs['name']?.toLowerCase() ??
          attrs['property']?.toLowerCase() ??
          '';
      final content = attrs['content'];
      if (key.isNotEmpty && content != null && content.isNotEmpty) {
        out.putIfAbsent(key, () => content);
      }
    }
    return out;
  }

  /// 去 `<script>` / `<style>`（含内容）→ 剥所有标签 → 实体解码 → 空白折叠
  static String _visibleText(String html) {
    final withoutCode = html
        .replaceAll(
            RegExp(r'<script\b[\s\S]*?</script>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(r'<style\b[\s\S]*?</style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        // 换行类标签换成空格，避免两个段落粘成一个词
        .replaceAll(
            RegExp(r'<(br|/p|/div|/li|/h[1-6])\b[^>]*>', caseSensitive: false),
            ' ');
    return _collapse(_decodeEntities(withoutCode.replaceAll(
        RegExp(r'<[^>]+>'), ' ')));
  }

  /// 空白折叠：所有连续空白（含换行）压成一个空格
  static String _collapse(String text) =>
      text.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

  /// 只处理最常见的几个实体：正文里出现 `&amp;` `&quot;` 会让模型读起来别扭
  static String _decodeEntities(String text) => text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
}

/// 一次原始抓取的落地结果（跳转后的 URL + HTML）
class _RawPage {
  final Uri url;
  final String html;

  const _RawPage({required this.url, required this.html});
}
