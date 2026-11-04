import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_web_readers.dart';
import 'package:fittrack/features/ai/data/local_page_fetcher.dart';
import 'package:fittrack/features/ai/data/web_tools_service.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

import 'fake_database.dart';

/// `fetch_url` 脱离 DeepSeek：本地抓取器 + 两条通道的兜底
///
/// 用户反馈"嘎教练打不开链接"的根因是：`fetch_url` 只走 DeepSeek 的
/// `/v1/tools/fetch`，而联网开关在非 DeepSeek 下把 web_search + fetch_url
/// 一起摘掉了。现在：读网页任何服务商都能用（本地抓），搜索仍然只有 DeepSeek。
void main() {
  /// 一段长得像真实页面的 HTML：标题 + 两种 meta 顺序 + script/style + 正文
  const html = '''
<html><head>
<title>10 分钟全身燃脂跟练｜B 站</title>
<meta content="每天十分钟，跟着做完就出汗" name="description">
<meta name="viewport" content="width=device-width">
<meta property="og:description" content="og 里的简介">
<style>.a{color:red}</style>
<script>window.__INIT__={"secret":"不该出现在正文里"}</script>
</head><body>
<h1>十分钟燃脂</h1>
<p>动作：深蹲、开合跳、平板支撑。</p>
<div>适合新手 &amp; 久坐党</div>
</body></html>
''';

  MockClient htmlClient({String body = html, int status = 200}) =>
      MockClient((request) async => http.Response.bytes(
            utf8.encode(body),
            status,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ));

  group('LocalPageFetcher：只靠 HTML 也能读出标题/简介/正文', () {
    test('标题、meta description（属性顺序反过来也认）、去 script/style 的正文',
        () async {
      final page = await LocalPageFetcher.fetch(
        'https://www.bilibili.com/video/BV1xx',
        client: htmlClient(),
      );

      expect(page.title, '10 分钟全身燃脂跟练｜B 站');
      expect(page.content, contains('每天十分钟，跟着做完就出汗'),
          reason: '名字叫 description 的 meta（content 在前也认）');
      expect(page.content, contains('深蹲、开合跳、平板支撑'));
      expect(page.content, isNot(contains('不该出现在正文里')),
          reason: 'script 内容必须剔掉');
      expect(page.content, isNot(contains('color:red')),
          reason: 'style 内容必须剔掉');
      expect(page.content, isNot(contains('<h1>')), reason: '标签要剥掉');
      expect(page.content, contains('适合新手 & 久坐党'), reason: '实体要解码');
    });

    test('没有 name=description 时回落 og:description', () async {
      const onlyOg = '<html><head><title>T</title>'
          '<meta property="og:description" content="og 简介"></head>'
          '<body>正文</body></html>';
      final page = await LocalPageFetcher.fetch('https://a.com/x',
          client: htmlClient(body: onlyOg));
      expect(page.content, contains('og 简介'));
    });

    test('超长正文截断到 6000 字符（与 DeepSeek 通道同口径）', () async {
      final long = '<html><head><title>T</title></head><body>'
          '${'字' * 20000}</body></html>';
      final page =
          await LocalPageFetcher.fetch('https://a.com/x', client: htmlClient(body: long));
      expect(page.content.length,
          LocalPageFetcher.maxContentChars + WebToolsService.truncatedMark.length);
      expect(page.content, endsWith(WebToolsService.truncatedMark));
      expect(LocalPageFetcher.maxContentChars, 6000);
    });

    test('非 http/https → 抛可读异常（不会真发请求）', () async {
      var called = false;
      final client = MockClient((r) async {
        called = true;
        return http.Response('', 200);
      });
      await expectLater(
        LocalPageFetcher.fetch('file:///etc/passwd', client: client),
        throwsA(isA<WebToolsException>()),
      );
      expect(called, isFalse);
    });

    test('HTTP 404 → 文案说"页面不存在"', () async {
      await expectLater(
        LocalPageFetcher.fetch('https://a.com/none',
            client: htmlClient(status: 404)),
        throwsA(predicate((e) =>
            e is WebToolsException && e.message.contains('不存在'))),
      );
    });

    test('超时 → 文案说"太慢"', () async {
      final slow = MockClient((r) async {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        return http.Response('', 200);
      });
      await expectLater(
        LocalPageFetcher.fetch('https://a.com/slow',
            client: slow, timeout: const Duration(milliseconds: 20)),
        throwsA(predicate((e) =>
            e is WebToolsException && e.message.contains('太慢'))),
      );
    });
  });

  group('fetch_url：非 DeepSeek 也能打开链接（本地抓取）', () {
    late AppDatabase db;
    late UserSettingsRepositoryImpl settings;

    setUp(() async {
      db = fakeDatabase();
      settings = UserSettingsRepositoryImpl(db);
    });
    tearDown(() async => db.close());

    Future<String> fetchVia({
      required String providerId,
      String? apiKey,
      required http.Client client,
      bool webOn = true,
    }) async {
      await settings.save(
        aiProviderId: providerId,
        aiApiKey: apiKey,
        aiWebSearchEnabled: webOn,
      );
      final readers = AiToolWebReaders(fakeToolRepos(db), client: client);
      return readers.execute(const AiToolCall(
        id: 'f1',
        name: AiToolSpecs.fetchUrl,
        argumentsJson: '{"url":"https://www.bilibili.com/video/BV1xx"}',
      ));
    }

    test('Minimax 用户：走本地抓取，回执标 source=local（这就是"能打开"）', () async {
      final res = jsonDecode(await fetchVia(
        providerId: 'minimax',
        apiKey: 'sk-test',
        client: htmlClient(),
      )) as Map<String, dynamic>;

      expect(res['ok'], true);
      expect(res['source'], 'local');
      expect(res['title'], '10 分钟全身燃脂跟练｜B 站');
      expect(res['content'], contains('深蹲、开合跳、平板支撑'));
    });

    test('DeepSeek 端点挂了 → 自动兜底本地抓取（不抛错、ok 仍为 true）', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.deepseek.com') {
          return http.Response('{"error":"internal"}', 500);
        }
        return http.Response.bytes(utf8.encode(html), 200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      });

      final res = jsonDecode(await fetchVia(
        providerId: 'deepseek',
        apiKey: 'sk-test',
        client: client,
      )) as Map<String, dynamic>;

      expect(res['ok'], true, reason: '服务端失败不该变成"打不开"');
      expect(res['source'], 'local');
      expect(res['content'], contains('深蹲、开合跳、平板支撑'));
    });

    test('DeepSeek 正常 → 用服务端抓取（source=deepseek）', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.deepseek.com') {
          return http.Response(
              jsonEncode({'title': '服务端标题', 'content': '服务端正文'}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('local should not be used', 200);
      });

      final res = jsonDecode(await fetchVia(
        providerId: 'deepseek',
        apiKey: 'sk-test',
        client: client,
      )) as Map<String, dynamic>;

      expect(res['ok'], true);
      expect(res['source'], 'deepseek');
      expect(res['title'], '服务端标题');
    });

    test('用户关掉「联网」→ fetch_url 也不可用（抛 AiToolException）', () async {
      await settings.save(
          aiProviderId: 'minimax', aiWebSearchEnabled: false);
      final readers = AiToolWebReaders(fakeToolRepos(db), client: htmlClient());
      await expectLater(
        readers.execute(const AiToolCall(
          id: 'f2',
          name: AiToolSpecs.fetchUrl,
          argumentsJson: '{"url":"https://a.com/x"}',
        )),
        throwsA(isA<AiToolException>()),
      );
    });

    test('非 DeepSeek 调 web_search → 明确说"服务商不支持"，不是网络错误', () async {
      await settings.save(aiProviderId: 'minimax', aiApiKey: 'sk-test');
      final readers = AiToolWebReaders(fakeToolRepos(db), client: htmlClient());
      await expectLater(
        readers.execute(const AiToolCall(
          id: 's1',
          name: AiToolSpecs.webSearch,
          argumentsJson: '{"query":"今天天气"}',
        )),
        throwsA(predicate((e) =>
            e is AiToolException &&
            e.message.contains(AiToolWebReaders.searchUnsupportedMessage))),
      );
    });
  });
}
