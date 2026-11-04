import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

import 'fake_database.dart';

/// 多 AI 服务商支持：服务商注册表 + 请求 URL/模型/thinking 按服务商切换 +
/// ai_provider_id 持久化。
void main() {
  group('服务商注册表', () {
    test('id 唯一，aiProviderById 找不到回落 DeepSeek', () {
      final ids = aiProviders.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length), reason: '服务商 id 不能重复');
      expect(aiProviderById('moonshot').name, contains('Kimi'));
      expect(aiProviderById(null).id, 'deepseek');
      expect(aiProviderById('不存在的').id, 'deepseek');
    });
  });

  group('AiService 按服务商发请求', () {
    http.Client sseClient(void Function(http.BaseRequest req, String body) onReq,
        {String content = '你好'}) {
      return MockClient.streaming((request, bodyStream) async {
        onReq(request, await bodyStream.bytesToString());
        final chunks = [
          'data: {"choices":[{"delta":{"content":"$content"}}]}\n\n',
          'data: [DONE]\n\n',
        ];
        return http.StreamedResponse(
            Stream.fromIterable(chunks.map(utf8.encode)), 200);
      });
    }

    test('非 DeepSeek：用该服务商 URL/模型，不带 thinking 字段', () async {
      late String url;
      late Map<String, dynamic> body;
      await AiService.streamChat(
        apiKey: 'k',
        messages: const [AiMessage(role: 'user', content: 'hi')],
        onDelta: (_) {},
        provider: aiProviderById('moonshot'),
        client: sseClient((req, raw) {
          url = req.url.toString();
          body = jsonDecode(raw) as Map<String, dynamic>;
        }),
      );
      expect(url, 'https://api.moonshot.cn/v1/chat/completions');
      expect(body['model'], 'kimi-k2-0711-preview');
      expect(body.containsKey('thinking'), isFalse,
          reason: '非 DeepSeek 是标准 OpenAI 兼容，带 thinking 可能被拒收');
    });

    test('DeepSeek：带 thinking 字段（关 thinking 保证工具回合不 400）', () async {
      late Map<String, dynamic> body;
      await AiService.streamChat(
        apiKey: 'k',
        messages: const [AiMessage(role: 'user', content: 'hi')],
        onDelta: (_) {},
        provider: aiProviderById('deepseek'),
        client: sseClient((req, raw) {
          body = jsonDecode(raw) as Map<String, dynamic>;
        }),
      );
      expect(body['thinking'], {'type': 'disabled'});
    });
  });

  test('aiProviderId 持久化：save 后能读回', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = UserSettingsRepositoryImpl(db);

    await repo.save(aiProviderId: 'moonshot', aiApiKey: 'sk-x');
    final got = await repo.get();
    expect(got?.aiProviderId, 'moonshot');
    expect(got?.aiApiKey, 'sk-x');

    // 再改回，确认不是只写不读
    await repo.save(aiProviderId: 'glm');
    expect((await repo.get())?.aiProviderId, 'glm');
  });
}
