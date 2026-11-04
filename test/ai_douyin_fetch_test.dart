import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_web_readers.dart';
import 'package:fittrack/features/ai/data/douyin_resolver.dart';
import 'package:fittrack/features/ai/data/local_page_fetcher.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

import 'fake_database.dart';

/// 抖音短链：移动 UA + 分享页解析 + **诚实兜底**
///
/// 实测根因：桌面 UA 落到 `www.douyin.com` 的 SPA 空壳（2.6KB、
/// `<title>【抖音】记录美好生活</title>`、没有 og:description）；移动 UA 会落到
/// `iesdouyin.com/share/video/{id}` 分享页（有 og 信息）。
///
/// 关键不是"能不能请求成功"，而是**请求成功但没内容时不能装作读到了** ——
/// 否则模型会按标题编动作。
void main() {
  const videoId = '7300000000000000000';

  /// 抖音桌面 UA 的落地页：只有站点名，没有正文
  const douyinShell = '<html><head><title>【抖音】记录美好生活</title>'
      '<script>window.__SHELL__={"a":1}</script></head>'
      '<body><div id="app"></div></body></html>';

  /// 分享页：给微信卡片用的那一版，带 og 标题/简介
  String sharePage({String title = '10 分钟全身燃脂跟练 - 抖音'}) => '''
<html><head>
<title>$title</title>
<meta property="og:title" content="$title">
<meta property="og:description" content="跟着做完就出汗，全程无器械，动作：深蹲、开合跳、平板支撑">
</head><body><div>抖音</div></body></html>
''';

  String biliPage() => '''
<html><head><title>10 分钟全身燃脂跟练｜B 站</title>
<meta property="og:description" content="每天十分钟，跟着做完就出汗">
</head><body><p>动作：深蹲、开合跳、平板支撑。适合新手与久坐党。</p></body></html>
''';

  http.Response html200(String body) => http.Response.bytes(
        utf8.encode(body),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );

  group('DouyinResolver（纯函数）', () {
    test('从三种 URL 形态里都能提出 video id', () {
      expect(
          DouyinResolver.videoIdOf(
              Uri.parse('https://www.douyin.com/video/$videoId')),
          videoId);
      expect(
          DouyinResolver.videoIdOf(
              Uri.parse('https://www.iesdouyin.com/share/video/$videoId/')),
          videoId);
      expect(
          DouyinResolver.videoIdOf(
              Uri.parse('https://www.douyin.com/?modal_id=$videoId')),
          videoId);
      expect(DouyinResolver.videoIdOf(Uri.parse('https://v.douyin.com/abc')),
          isNull);
    });

    test('站点名标题判定：只有站点名才算"读不到"', () {
      expect(DouyinResolver.isGenericTitle('【抖音】记录美好生活'), isTrue);
      expect(DouyinResolver.isGenericTitle('抖音'), isTrue);
      expect(DouyinResolver.isGenericTitle('哔哩哔哩'), isTrue);
      expect(DouyinResolver.isGenericTitle('抖音-记录美好生活'), isTrue);
      expect(DouyinResolver.isGenericTitle('10 分钟全身燃脂跟练｜B 站'), isFalse);
      expect(DouyinResolver.isGenericTitle(''), isTrue);
    });
  });

  group('LocalPageFetcher：抖音走移动 UA + 分享页', () {
    late List<Uri> hits;

    MockClient douyinClient({
      String share = '',
      String shell = douyinShell,
      String? redirectTo,
    }) {
      hits = [];
      return MockClient((request) async {
        hits.add(request.url);
        final url = request.url;
        if (url.host == 'v.douyin.com') {
          return http.Response('', 302, headers: {
            'location': redirectTo ?? 'https://www.douyin.com/video/$videoId',
          });
        }
        if (url.host == 'www.iesdouyin.com') {
          return html200(share.isEmpty ? sharePage() : share);
        }
        return html200(shell);
      });
    }

    test('短链 302 → 提 id → 分享页取 og 标题/简介', () async {
      final page = await LocalPageFetcher.fetch('https://v.douyin.com/abc123',
          client: douyinClient());

      expect(page.contentUnavailable, isFalse);
      expect(page.title, contains('10 分钟全身燃脂跟练'));
      expect(page.content, contains('深蹲、开合跳、平板支撑'),
          reason: '简介（og:description）要进正文');
      // 落地的 SPA 壳与分享页都应该被访问到（说明确实按 id 重组了请求）
      expect(hits.map((u) => u.host).toSet(),
          containsAll(['v.douyin.com', 'www.iesdouyin.com']));
      expect(hits.any((u) => u.path.contains('/share/video/$videoId')), isTrue);
    });

    test('分享页也只有站点名 → 标 contentUnavailable（不装作读到了）', () async {
      final page = await LocalPageFetcher.fetch('https://v.douyin.com/abc123',
          client: douyinClient(share: douyinShell));

      expect(page.contentUnavailable, isTrue);
      expect(page.title, contains('抖音'));
    });

    test('短链跳转后没有视频 id → 走通用抓取，不崩', () async {
      final page = await LocalPageFetcher.fetch('https://v.douyin.com/abc123',
          client: douyinClient(
              redirectTo: 'https://www.douyin.com/', shell: douyinShell));

      // 不抛异常即可；壳子当然读不到正文
      expect(page, isA<LocalPage>());
      expect(page.contentUnavailable, isTrue);
      expect(page.content, isNot(contains('__SHELL__')),
          reason: 'script 内容必须剔掉');
    });
  });

  group('_fetchUrl 回执：读不到正文要 ok:false（别让模型编）', () {
    late AppDatabase db;
    late UserSettingsRepositoryImpl settings;

    setUp(() async {
      db = fakeDatabase();
      settings = UserSettingsRepositoryImpl(db);
      await settings.save(aiProviderId: 'minimax', aiApiKey: 'sk-test');
    });
    tearDown(() async => db.close());

    Future<Map<String, dynamic>> fetchWith(
      http.Client client, {
      String url = 'https://v.douyin.com/abc123',
    }) async {
      final readers = AiToolWebReaders(fakeToolRepos(db), client: client);
      final res = await readers.execute(AiToolCall(
        id: 'f1',
        name: AiToolSpecs.fetchUrl,
        argumentsJson: jsonEncode({'url': url}),
      ));
      return jsonDecode(res) as Map<String, dynamic>;
    }

    test('抖音能读到分享页时：ok:true、source=local、标题简介都在', () async {
      final res = await fetchWith(MockClient((request) async {
        if (request.url.host == 'v.douyin.com') {
          return http.Response('', 302,
              headers: {'location': 'https://www.douyin.com/video/$videoId'});
        }
        if (request.url.host == 'www.iesdouyin.com') return html200(sharePage());
        return html200(douyinShell);
      }));

      expect(res['ok'], true);
      expect(res['source'], 'local');
      expect(res['title'], contains('10 分钟全身燃脂跟练'));
      expect(res['content'], contains('深蹲'));
    });

    test('抖音只拿到 SPA 壳：**ok:false** 且错误含「读不到视频正文」', () async {
      final res = await fetchWith(MockClient((request) async {
        if (request.url.host == 'v.douyin.com') {
          return http.Response('', 302,
              headers: {'location': 'https://www.douyin.com/video/$videoId'});
        }
        return html200(douyinShell);
      }));

      expect(res['ok'], false, reason: '不能把"空壳"当成功回执');
      expect(res['error'], contains('读不到视频正文'));
      expect(res['url'], contains('douyin.com'));
      expect(res.containsKey('content'), isFalse,
          reason: '不许带空 content 回去，否则模型会以为读到了');
    });

    test('非抖音站点不受影响：B 站仍能拿到 title + og:description', () async {
      final res = await fetchWith(
        MockClient((request) async => html200(biliPage())),
        url: 'https://www.bilibili.com/video/BV1xx411c7mD',
      );

      expect(res['ok'], true);
      expect(res['source'], 'local');
      expect(res['title'], contains('10 分钟全身燃脂跟练'));
      expect(res['content'], contains('每天十分钟'));
    });
  });
}
