import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'fake_database.dart';
import 'package:fittrack/core/services/web_tools_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/data/ai_tool_web_readers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

/// 联网搜索 / 读网页（DeepSeek tools 接口）的纯逻辑回归
///
/// 覆盖四类不变量：
/// 1. fetch_url 的链接校验（协议 / 账号密码 / 内网地址 / 超长一律拒绝）
/// 2. search 的响应解析（条数上限、summary 回落 snippet、超长截断、错误文案）
/// 3. fetch 的响应解析（title / content，正文 6000 字符截断）
/// 4. 两个新工具都是只读、自动执行，且不破坏原有工具集合划分
///
/// 全部走 MockClient / 纯函数，不连真实网络。
void main() {
  // ═══════════ 1. fetch_url 的链接安全校验 ═══════════

  group('fetch_url 链接校验', () {
    test('合法 http / https 放行，并回传解析后的 Uri', () {
      final https = AiToolArgs.fetchUrl({'url': ' https://example.com/a?b=1 '});
      expect(https.scheme, 'https');
      expect(https.host, 'example.com');
      expect(https.query, 'b=1', reason: '查询串不能被裁掉');

      final httpUrl =
          AiToolArgs.fetchUrl({'url': 'http://news.sina.com.cn/x.html'});
      expect(httpUrl.scheme, 'http');
      expect(httpUrl.host, 'news.sina.com.cn');
    });

    test('非法协议 / 带账号密码 / 空链接一律拒绝', () {
      const bad = <String>[
        'ftp://example.com/file.md',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'http://user:pw@a.com/post',
        'http://user@a.com/post',
      ];
      for (final url in bad) {
        expect(
          () => AiToolArgs.fetchUrl({'url': url}),
          throwsA(isA<AiToolException>()
              .having((e) => e.message, 'message', contains('这个链接不能抓取'))),
          reason: '$url 不该被放行',
        );
      }
      expect(() => AiToolArgs.fetchUrl({'url': ''}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.fetchUrl({}), throwsA(isA<AiToolException>()));
    });

    test('内网 / 本机 / 链路本地 / .local 一律拒绝', () {
      const bad = <String>[
        'http://localhost:8080/x',
        'http://127.0.0.1/x',
        'http://127.9.9.9/',
        'http://10.1.2.3/',
        'http://192.168.1.1/',
        'http://172.20.0.1/',
        'http://172.16.0.1/',
        'http://172.31.255.255/',
        'http://169.254.1.1/',
        'http://0.0.0.0/',
        'http://[::1]/',
        'http://[::1]:8080/admin',
        'http://nas.local/file',
        'http://intranet/secret',
      ];
      for (final url in bad) {
        expect(
          () => AiToolArgs.fetchUrl({'url': url}),
          throwsA(isA<AiToolException>()
              .having((e) => e.message, 'message', contains('内网或格式不支持'))),
          reason: '$url 指向内网，必须拒绝',
        );
      }
    });

    test('公网 IP 与带端口的域名照常放行', () {
      expect(AiToolArgs.fetchUrl({'url': 'http://1.1.1.1/x'}).host, '1.1.1.1');
      expect(
          AiToolArgs.fetchUrl({'url': 'https://mp.weixin.qq.com/s/abc'}).host,
          'mp.weixin.qq.com');
      expect(
          AiToolArgs.fetchUrl({'url': 'https://example.com:8443/'}).port, 8443);
      expect(
          AiToolArgs.fetchUrl({'url': 'http://172.32.0.1/'}).host, '172.32.0.1',
          reason: '172.32 不在 172.16~31 私网段里');
    });

    test('超长链接（>2048）拒绝', () {
      final long = 'https://example.com/${'a' * 2100}';
      expect(
        () => AiToolArgs.fetchUrl({'url': long}),
        throwsA(isA<AiToolException>()
            .having((e) => e.message, 'message', contains('不能抓取'))),
      );
      expect(AiToolArgs.maxUrlLength, 2048);
    });

    test('web_search 关键词与条数校验', () {
      expect(AiToolArgs.webSearchQuery({'query': '  今天金价  '}), '今天金价');
      expect(() => AiToolArgs.webSearchQuery({'query': '  '}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.webSearchQuery({'query': 'x' * 129}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.webSearchQuery({'query': 'x' * 128}).length, 128);

      expect(AiToolArgs.webSearchCount({}), 5, reason: '缺省 5 条');
      expect(AiToolArgs.webSearchCount({'count': 3}), 3);
      expect(AiToolArgs.webSearchCount({'count': '4'}), 4);
      expect(() => AiToolArgs.webSearchCount({'count': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.webSearchCount({'count': 11}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.webSearchCount({'count': 'abc'}),
          throwsA(isA<AiToolException>()));
    });
  });

  // ═══════════ 2. search 响应解析 ═══════════

  group('search 请求与解析', () {
    test('请求体：need_content=false，count 透传，路径是 /v1/tools/search', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json({'results': <Object>[]});
      });

      await WebToolsService.search(
        apiKey: 'sk-test',
        query: '今天金价',
        count: 3,
        oriQuestion: '金价多少',
        client: client,
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/v1/tools/search');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['query'], '今天金价');
      expect(body['count'], 3);
      expect(body['need_content'], isFalse, reason: '只要 summary，省 token');
      expect(body['ori_question'], '金价多少');
    });

    test('解析结果：字段映射正确，summary 为空回落 snippet', () async {
      final client = MockClient((_) async => _json({
            'results': [
              {
                'title': '金价突破 800',
                'url': 'https://finance.example.com/a',
                'summary': '  国际金价上涨  ',
                'site_name': '财经网',
                'date': '2026-10-17',
                'authority': 3,
              },
              {
                'title': '没有 summary 的站点',
                'url': 'https://b.example.com/b',
                'summary': '',
                'snippet': '这是摘要片段',
                'authority': -1,
              },
            ],
          }));

      final results = await WebToolsService.search(
          apiKey: 'k', query: '金价', client: client);

      expect(results, hasLength(2));
      expect(results.first.title, '金价突破 800');
      expect(results.first.url, 'https://finance.example.com/a');
      expect(results.first.summary, '国际金价上涨');
      expect(results.first.siteName, '财经网');
      expect(results.first.date, '2026-10-17');
      expect(results.first.authority, 3);
      expect(results[1].summary, '这是摘要片段', reason: 'summary 为空要回落 snippet');
      expect(results[1].siteName, isNull);
      expect(results[1].date, isNull);
    });

    test('超过 5 条只回传 5 条；单条 summary 超 500 字被截断', () async {
      final longSummary = '很' * 900;
      final client = MockClient((_) async => _json({
            'results': [
              for (var i = 1; i <= 8; i++)
                {
                  'title': '结果 $i',
                  'url': 'https://example.com/$i',
                  'summary': i == 1 ? longSummary : '短摘要 $i',
                },
            ],
          }));

      final results =
          await WebToolsService.search(apiKey: 'k', query: 'q', client: client);

      expect(results, hasLength(WebToolsService.maxResults));
      expect(results.length, 5);
      expect(results.first.summary.length, 501, reason: '500 字 + 省略号');
      expect(results.first.summary.endsWith('…'), isTrue);
    });

    test('错误码映射成中文：401 / 402 / 429 / 5xx', () async {
      Future<WebToolsException> failureOf(int status, String body) async {
        final client = MockClient((_) async => _json(body, status: status));
        try {
          await WebToolsService.search(apiKey: 'k', query: 'q', client: client);
        } on WebToolsException catch (e) {
          return e;
        }
        fail('$status 应当抛 WebToolsException');
      }

      final unauthorized =
          await failureOf(401, '{"error":{"message":"Authentication Fails"}}');
      expect(unauthorized.message, contains('API Key'));
      expect(unauthorized.isNetworkError, isFalse, reason: '鉴权错误不该触发重试');

      expect((await failureOf(402, '')).message, contains('余额'));
      expect((await failureOf(429, '')).message, contains('频繁'));
      expect((await failureOf(503, '')).message, contains('暂时不可用'));
      // 服务端 error.message 要拼进去，便于自助排查
      expect(unauthorized.message, contains('Authentication Fails'));
    });

    test('网络异常标记 isNetworkError，超时文案可读', () async {
      final client = MockClient((_) async => throw const SocketExceptionStub());
      try {
        await WebToolsService.search(apiKey: 'k', query: 'q', client: client);
        fail('应当抛出 WebToolsException');
      } on WebToolsException catch (e) {
        expect(e.isNetworkError, isTrue);
        expect(e.message, isNotEmpty);
      }
    });
  });

  // ═══════════ 3. fetch 响应解析 ═══════════

  group('fetch 请求与解析', () {
    test('请求体只带 url，路径是 /v1/tools/fetch', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _json({'title': '标题', 'content': '# 正文'});
      });

      final page = await WebToolsService.fetchPage(
          apiKey: 'k', url: 'https://example.com/a', client: client);

      expect(captured.url.path, '/v1/tools/fetch');
      expect(jsonDecode(captured.body), {'url': 'https://example.com/a'});
      expect(page.title, '标题');
      expect(page.content, '# 正文');
    });

    test('正文超过 6000 字符被截断并带「内容已截断」标记', () async {
      final long = 'a' * 9000;
      final client = MockClient((_) async => _json({
            'title': '长文',
            'content': long,
          }));

      final page = await WebToolsService.fetchPage(
          apiKey: 'k', url: 'https://example.com/long', client: client);

      expect(
          page.content.length,
          WebToolsService.maxContentChars +
              WebToolsService.truncatedMark.length);
      expect(page.content.startsWith('a' * 100), isTrue);
      expect(page.content.endsWith(WebToolsService.truncatedMark), isTrue);
      expect(page.content, contains('内容已截断'));
    });

    test('正好 6000 字符不截断（不留多余标记）', () {
      final exact = 'b' * WebToolsService.maxContentChars;
      expect(WebToolsService.clipContent(exact), exact);
      expect(WebToolsService.clipContent(exact).length, 6000);
    });

    test('缺字段时回落空串，不抛异常', () async {
      final client = MockClient((_) async => _json({'content': null}));
      final page = await WebToolsService.fetchPage(
          apiKey: 'k', url: 'https://example.com/empty', client: client);
      expect(page.title, '');
      expect(page.content, '');
    });
  });

  // ═══════════ 4. 工具集合与预览层 ═══════════

  group('两个新工具都是只读、自动执行', () {
    test('25 个工具、唯一、写/只读互斥并集全覆盖，危险 = 四个删除类', () {
      final registered = AiToolSpecs.defs
          .map((d) => (d['function'] as Map)['name'] as String)
          .toList();

      expect(registered, hasLength(25), reason: '工具总数应为 24');
      expect(registered.toSet(), hasLength(25), reason: '工具名不能重复');
      expect({
        ...AiToolSpecs.writeTools,
        ...AiToolSpecs.readOnlyTools
      }, registered.toSet(), reason: '写 / 只读两集合必须正好划分已注册的工具');
      expect(AiToolSpecs.writeTools.intersection(AiToolSpecs.readOnlyTools),
          isEmpty,
          reason: '同一工具不能既写又只读（否则可以绕过确认）');
      expect(
          AiToolSpecs.destructiveTools,
          {
            AiToolSpecs.deleteRecords,
            AiToolSpecs.deleteMeasurement,
            AiToolSpecs.deleteTemplate,
            AiToolSpecs.wipeAllData,
          },
          reason: '24 个里有三个危险操作：删记录 / 删身体记录 / 清空全部数据');
      expect(AiToolSpecs.destructiveTools.difference(AiToolSpecs.writeTools),
          isEmpty);

      for (final name in [AiToolSpecs.webSearch, AiToolSpecs.fetchUrl]) {
        expect(AiToolSpecs.readOnlyTools, contains(name));
        expect(AiToolSpecs.writeTools, isNot(contains(name)));
        expect(AiToolSpecs.destructiveTools, isNot(contains(name)));
        expect(AiToolSpecs.isReadOnly(name), isTrue);
      }
    });

    test('preview：需要确认 = false、不是危险操作、详情文案可读', () async {
      final handler = AiToolWebReaders(_repos(apiKey: 'sk-test'));

      final search = await handler.preview(const AiToolCall(
        id: 'call_ws',
        name: AiToolSpecs.webSearch,
        argumentsJson: '{"query":"今天金价"}',
      ));
      expect(search.label, '联网搜索');
      expect(search.detail, '搜索"今天金价"');
      expect(search.needsConfirm, isFalse);
      expect(search.isDestructive, isFalse);

      final fetch = await handler.preview(const AiToolCall(
        id: 'call_fu',
        name: AiToolSpecs.fetchUrl,
        argumentsJson: '{"url":"https://mp.weixin.qq.com/s/abc"}',
      ));
      expect(fetch.label, '读取网页');
      expect(fetch.detail, '读取：mp.weixin.qq.com');
      expect(fetch.needsConfirm, isFalse);
      expect(fetch.isDestructive, isFalse);
    });

    test('preview 阶段就拦掉内网链接（不发网络请求）', () async {
      var called = 0;
      final handler = AiToolWebReaders(
        _repos(apiKey: 'sk-test'),
        client: MockClient((_) async {
          called++;
          return _json({'title': '', 'content': ''});
        }),
      );

      await expectLater(
        handler.preview(const AiToolCall(
          id: 'call_bad',
          name: AiToolSpecs.fetchUrl,
          argumentsJson: '{"url":"http://192.168.1.1/admin"}',
        )),
        throwsA(isA<AiToolException>()),
      );
      expect(called, 0, reason: '非法链接不该产生任何网络请求');
    });

    test('联网开关关闭时 preview / execute 都拒绝（不发网络请求）', () async {
      var called = 0;
      final handler = AiToolWebReaders(
        _repos(apiKey: 'sk-test', webEnabled: false),
        client: MockClient((_) async {
          called++;
          return _json({'results': [], 'title': '', 'content': ''});
        }),
      );

      for (final call in [
        const AiToolCall(
          id: 'call_off_1',
          name: AiToolSpecs.webSearch,
          argumentsJson: '{"query":"今天金价"}',
        ),
        const AiToolCall(
          id: 'call_off_2',
          name: AiToolSpecs.fetchUrl,
          argumentsJson: '{"url":"https://example.com/a"}',
        ),
      ]) {
        await expectLater(
          handler.preview(call),
          throwsA(isA<AiToolException>().having((e) => e.message, 'message',
              AiToolWebReaders.webDisabledMessage)),
        );
        await expectLater(
          handler.execute(call),
          throwsA(isA<AiToolException>().having((e) => e.message, 'message',
              AiToolWebReaders.webDisabledMessage)),
        );
      }
      expect(called, 0, reason: '关闭联网后一次搜索请求都不应该发出去');
    });

    test('handler 白名单只认这两个工具，别的工具直接拒绝', () {
      final handler = AiToolWebReaders(_repos(apiKey: null));
      expect(handler.toolNames, {AiToolSpecs.webSearch, AiToolSpecs.fetchUrl});
      expect(handler.supports(AiToolSpecs.queryStats), isFalse);
      expect(
        () => handler.execute(const AiToolCall(
          id: 'call_x',
          name: AiToolSpecs.deleteRecords,
          argumentsJson: '{"type":"food"}',
        )),
        throwsA(isA<AiToolException>()),
      );
    });
  });

  // ═══════════ 5. 执行结果映射 ═══════════

  group('execute 回传给模型的 JSON', () {
    test('web_search：ok + ≤5 条，只带必要字段', () async {
      final handler = AiToolWebReaders(
        _repos(apiKey: 'sk-test'),
        client: MockClient((_) async => _json({
              'results': [
                for (var i = 1; i <= 7; i++)
                  {
                    'title': 'T$i',
                    'url': 'https://example.com/$i',
                    'summary': 'S$i',
                    'site_name': '站点$i',
                    'date': '2026-10-0$i',
                    'authority': 2,
                    'content': '正文不该回传' * 100,
                    'site_icon': 'https://example.com/icon.png',
                  },
              ],
            })),
      );

      final raw = await handler.execute(const AiToolCall(
        id: 'call_ws',
        name: AiToolSpecs.webSearch,
        argumentsJson: '{"query":"金价","count":7}',
      ));
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['ok'], isTrue);
      expect(result['query'], '金价');
      final items = result['results'] as List<dynamic>;
      expect(items, hasLength(5), reason: '回传给模型的最多 5 条');
      final first = items.first as Map<String, dynamic>;
      expect(first.keys.toSet(),
          {'title', 'url', 'summary', 'site_name', 'date', 'authority'});
      expect(raw, isNot(contains('正文不该回传')), reason: 'content 不进上下文');
    });

    test('fetch_url：ok + title + content + url', () async {
      final handler = AiToolWebReaders(
        _repos(apiKey: 'sk-test'),
        client: MockClient(
            (_) async => _json({'title': '文章标题', 'content': '# 正文\n内容'})),
      );

      final raw = await handler.execute(const AiToolCall(
        id: 'call_fu',
        name: AiToolSpecs.fetchUrl,
        argumentsJson: '{"url":"https://example.com/post"}',
      ));
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['ok'], isTrue);
      expect(result['title'], '文章标题');
      expect(result['content'], '# 正文\n内容');
      expect(result['url'], 'https://example.com/post');
    });

    test('接口失败返回 ok:false（交给模型说"没搜到"，不打断整轮）', () async {
      final handler = AiToolWebReaders(
        _repos(apiKey: 'sk-test'),
        client: MockClient((_) async => _json('', status: 429)),
      );

      final raw = await handler.execute(const AiToolCall(
        id: 'call_ws',
        name: AiToolSpecs.webSearch,
        argumentsJson: '{"query":"金价"}',
      ));
      final result = jsonDecode(raw) as Map<String, dynamic>;

      expect(result['ok'], isFalse);
      expect(result['error'], contains('频繁'));
    });

    test('没配置 API Key：抛 AiToolException 并说明缺什么', () async {
      final handler = AiToolWebReaders(_repos(apiKey: null));
      await expectLater(
        handler.execute(const AiToolCall(
          id: 'call_ws',
          name: AiToolSpecs.webSearch,
          argumentsJson: '{"query":"金价"}',
        )),
        throwsA(isA<AiToolException>()
            .having((e) => e.message, 'message', contains('API Key'))),
      );
      expect(AiToolWebReaders.noKeyMessage, '还没配置 API Key');
    });
  });

  // ═══════════ 6. 提示词与设置页文案 ═══════════

  group('提示词补上联网规则', () {
    test('四条新规则都在 # 工具使用 段里', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);

      // ① 时效性信息先搜
      expect(prompt, contains('web_search'));
      expect(prompt, contains('时效性'));
      expect(prompt, contains('不要凭记忆编'));
      // ② 链接用 fetch_url，视频看不到画面要说清
      expect(prompt, contains('fetch_url'));
      expect(prompt, contains('公众号'));
      expect(prompt, contains('看不到画面'));
      // ③ 来源格式：来源：站点名 + 链接，最多 3 条
      expect(prompt, contains('来源：'));
      expect(prompt, contains('最多 3 条'));
      // ④ 失败直说，不编造
      expect(prompt, contains('没搜到可靠信息'));
    });

    test('计费说明文案与设置页共用', () {
      expect(WebToolsService.priceNote, contains('¥5 / 1000 次'));
      expect(WebToolsService.priceNote, contains('仅在需要时调用'));
    });
  });
}

// ═══════════════════════ 测试辅助 ═══════════════════════

/// 构造 JSON 响应（正文按 UTF-8 编码，避免中文乱码）
http.Response _json(Object? payload, {int status = 200}) => http.Response.bytes(
      utf8.encode(payload is String ? payload : jsonEncode(payload)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 模拟网络异常（名字带 Stub 以免被当成真实的 SocketException）
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketException: Connection refused';
}

/// 只关心 settings 的仓储集合（其余仓储一旦被碰就报错）
AiToolRepos _repos({required String? apiKey, bool webEnabled = true}) =>
    AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
      database: fakeDatabase(),
      body: const _UntouchedBodyRepo(),
      water: const _UntouchedWaterRepo(),
      workout: const _UntouchedWorkoutRepo(),
      diet: const _UntouchedDietRepo(),
      goal: const _UntouchedGoalRepo(),
      settings: _StubSettingsRepo(apiKey, webEnabled: webEnabled),
      exercise: const _UntouchedExerciseRepo(),
      template: const _UntouchedTemplateRepo(),
    );

/// 设置仓储：有 key 就返回带 key 的设置，无 key 返回 null
class _StubSettingsRepo implements UserSettingsRepository {
  const _StubSettingsRepo(this.apiKey, {this.webEnabled = true});

  final String? apiKey;

  /// 「联网搜索」开关（v20）
  final bool webEnabled;

  @override
  Future<UserSettingsEntity?> get() async => apiKey == null
      ? null
      : UserSettingsEntity(
          id: 1,
          aiApiKey: apiKey,
          aiWebSearchEnabled: webEnabled,
        );

  @override
  Future<UserSettingsEntity> save({
    double? heightCm,
    double? targetWeightKg,
    DateTime? birthDate,
    String? gender,
    String? activityLevel,
    String? pinCode,
    bool? lockEnabled,
    double? speechRate,
    double? speechPitch,
    String? ttsVoice,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    String? themeMode,
    int? defaultTrainingSec,
    int? defaultRestSec,
    int? restShortSec,
    int? restLongSec,
    bool? autoBackupEnabled,
    String? aiApiKey,
    String? aiStyle,
    String? aiConstraints,
    String? aiReplyLength,
    double? aiTemperature,
    String? aiPersonaCustom,
    bool? aiWebSearchEnabled,
    int? dailyCalorieTarget,
    double? proteinTargetG,
    double? carbsTargetG,
    double? fatTargetG,
  }) async =>
      throw UnimplementedError('联网工具不该写设置');

  @override
  @override
  Future<void> saveNickname(String? nickname) async {}

  @override
  Future<void> saveAvatarPath(String? avatarPath) async {}

  @override
  Future<void> incrementAiHealthOverrideCount() async =>
      throw UnimplementedError('联网工具不该改误报计数');

  @override
  Future<void> resetAiHealthOverrideCount() async =>
      throw UnimplementedError('联网工具不该改误报计数');

  @override
  Future<void> clearLock() async =>
      throw UnimplementedError('联网工具不该动隐私锁');
}

// ═══════════ 不该被碰到的仓储 ═══════════

class _UntouchedBodyRepo implements BodyMetricRepository {
  const _UntouchedBodyRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 body 仓储');
}

class _UntouchedWaterRepo implements WaterRepository {
  const _UntouchedWaterRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 water 仓储');
}

class _UntouchedWorkoutRepo implements WorkoutRepository {
  const _UntouchedWorkoutRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 workout 仓储');
}

class _UntouchedDietRepo implements DietRepository {
  const _UntouchedDietRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 diet 仓储');
}

class _UntouchedGoalRepo implements GoalRepository {
  const _UntouchedGoalRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 goal 仓储');
}

class _UntouchedExerciseRepo implements ExerciseRepository {
  const _UntouchedExerciseRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 exercise 仓储');
}

class _UntouchedTemplateRepo implements WorkoutTemplateRepository {
  const _UntouchedTemplateRepo();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('联网工具不该访问 template 仓储');
}
