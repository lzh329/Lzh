import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';

/// v1.4 回归补充：真正发出的 HTTP 请求体 + 图片多模态结构 + 复制按钮
///
/// 这里不做任何网络请求（MockClient 拦截）、不碰数据库，只验证「发出去的东西
/// 长什么样」——400 修复与视觉消息的关键都在请求体上。
void main() {
  /// 捕获请求体并回一段合法 SSE 的 MockClient
  http.Client capturingClient(void Function(String body) onBody,
      {String sseText = '你好'}) {
    return MockClient.streaming((request, bodyStream) async {
      onBody(await bodyStream.bytesToString());
      final chunks = [
        'data: {"choices":[{"delta":{"content":"$sseText"}}]}\n\n',
        'data: [DONE]\n\n',
      ];
      return http.StreamedResponse(
          Stream.fromIterable(chunks.map(utf8.encode)), 200);
    });
  }

  group('工具回合请求体（端到端：AiToolContext → HTTP body）', () {
    late Map<String, dynamic> decoded;
    late List<dynamic> messages;

    setUp(() async {
      final ctx = AiToolContext()
        ..append(
          const AiToolCall(
            id: 'call_9',
            name: 'log_weight',
            argumentsJson: '{"weight_jin":160}',
          ),
          '{"ok":true}',
        );
      late String raw;
      await AiService.streamChat(
        apiKey: 'test-key',
        messages: [
          const AiMessage(role: 'system', content: '你是嘎教练'),
          const AiMessage(role: 'user', content: '我 160 斤'),
          ...ctx.messages,
        ],
        tools: AiToolSpecs.defs,
        onDelta: (_) {},
        client: capturingClient((body) => raw = body),
      );
      decoded = jsonDecode(raw) as Map<String, dynamic>;
      messages = decoded['messages'] as List<dynamic>;
    });

    test('顶层固定关闭 thinking，且 stream / temperature 正常', () {
      expect(decoded['thinking'], {'type': 'disabled'},
          reason: 'thinking 一旦开启，工具回合必须回传 reasoning_content，否则 400');
      expect(decoded['stream'], isTrue);
      expect(decoded['temperature'], AiService.defaultTemperature);
    });

    test('tools 与 tool_choice 仍在（关 thinking 不影响工具能力）', () {
      final tools = decoded['tools'] as List<dynamic>;
      expect(tools, hasLength(25));
      expect(decoded['tool_choice'], 'auto');
    });

    test('消息顺序与角色完整：system → user → assistant(tool_calls) → tool', () {
      expect(messages, hasLength(4));
      expect(messages.map((m) => (m as Map)['role']).toList(),
          ['system', 'user', 'assistant', 'tool']);
    });

    test('system / user 消息 content 都是字符串（没被误改成 null）', () {
      final system = messages[0] as Map<String, dynamic>;
      final user = messages[1] as Map<String, dynamic>;
      expect(system['content'], isA<String>());
      expect(user['content'], '我 160 斤');
      expect(system.containsKey('tool_calls'), isFalse);
      expect(system.containsKey('tool_call_id'), isFalse);
      expect(user.containsKey('tool_calls'), isFalse);
    });

    test('assistant 工具调用消息 content 为 null 且 tool_calls 结构合法', () {
      final assistant = messages[2] as Map<String, dynamic>;
      expect(assistant.containsKey('content'), isTrue);
      expect(assistant['content'], isNull, reason: '空正文必须发 null，发空串会 400');
      final calls = assistant['tool_calls'] as List<dynamic>;
      expect(calls, hasLength(1));
      final call = calls.first as Map<String, dynamic>;
      expect(call['id'], 'call_9');
      expect(call['type'], 'function');
      final fn = call['function'] as Map<String, dynamic>;
      expect(fn['name'], 'log_weight');
      expect(jsonDecode(fn['arguments'] as String), {'weight_jin': 160});
    });

    test('tool 结果消息带 name + tool_call_id', () {
      final tool = messages[3] as Map<String, dynamic>;
      expect(tool['tool_call_id'], 'call_9');
      expect(tool['name'], 'log_weight', reason: 'DeepSeek 要求 tool 消息带 name');
      expect(tool['content'], '{"ok":true}');
    });

    test('进请求体后所有工具 schema 都没有空 required 数组', () {
      for (final def in decoded['tools'] as List<dynamic>) {
        final fn = (def as Map)['function'] as Map;
        final params = fn['parameters'] as Map;
        if (params.containsKey('required')) {
          expect(params['required'] as List, isNotEmpty,
              reason: '${fn['name']} 的 required 是空数组，网关会判非法 schema → 400');
        }
        expect(params['type'], 'object');
        expect(params['properties'], isA<Map>());
      }
    });
  });

  group('图片消息请求体（多模态）', () {
    late Directory tmp;
    late File image;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('fittrack_qa_img');
      image = File('${tmp.path}/meal.jpg')
        ..writeAsBytesSync(List<int>.filled(1024, 7));
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('带图消息的内容是数组：text 段 + image_url 段（data:image/jpeg;base64,）', () async {
      final payload = await AiChatImageFlow.buildUserPayload(
          text: '这碗面多少热量', image: image);
      expect(payload.content, isA<List>());

      late String raw;
      await AiService.streamChat(
        apiKey: 'test-key',
        messages: [AiMessage(role: 'user', content: payload.content)],
        onDelta: (_) {},
        client: capturingClient((body) => raw = body, sseText: '约 620 千卡'),
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final sent = (decoded['messages'] as List).first as Map<String, dynamic>;
      final parts = sent['content'] as List<dynamic>;
      expect(parts, hasLength(2));
      expect(sent['role'], 'user');

      final textPart = parts.first as Map<String, dynamic>;
      expect(textPart['type'], 'text');
      expect(textPart['text'], '这碗面多少热量');

      final imagePart = parts.last as Map<String, dynamic>;
      expect(imagePart['type'], 'image_url');
      final url = (imagePart['image_url'] as Map)['url'] as String;
      expect(url, startsWith('data:image/jpeg;base64,'));
      expect(base64Decode(url.split(',').last).length, 1024,
          reason: 'base64 应与原图字节一一对应');
    });

    test('只发图片（文字为空）也能组装：text 段用默认提问', () async {
      final payload =
          await AiChatImageFlow.buildUserPayload(text: '   ', image: image);
      final parts = payload.content as List<Map<String, dynamic>>;
      expect(parts.first['type'], 'text');
      expect(parts.first['text'], AiChatImageFlow.defaultText);
      expect(parts.last['type'], 'image_url');
    });

    test('落库文本只有文字 + [图片]，绝不含 base64', () async {
      final payload =
          await AiChatImageFlow.buildUserPayload(text: '午饭', image: image);
      expect(payload.historyText, '午饭 [图片]');
      expect(payload.historyText, isNot(contains('base64')));
      expect(payload.historyText, isNot(contains('data:image')));
    });

    test('气泡展示 / 复制取到的文字也不含 base64', () async {
      final payload =
          await AiChatImageFlow.buildUserPayload(text: '午饭', image: image);
      final msg = AiMessage(role: 'user', content: payload.content);
      expect(msg.textOnly, '午饭');
      expect(msg.textOnly, isNot(contains('base64')));
    });
  });

  group('图片体积上限（真实文件读取）', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('fittrack_qa_size'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('小图能编码成 data URL', () async {
      final file = File('${tmp.path}/small.jpg')
        ..writeAsBytesSync(List<int>.filled(2048, 1));
      final url = await AiChatImageFlow.toDataUrl(file);
      expect(url, startsWith('data:image/jpeg;base64,'));
      expect(AiChatImageFlow.isOversize(url.split(',').last), isFalse);
    });

    test('超过 2MB base64 的图被拒，且错误文案可直接展示', () async {
      // base64 约 4/3 倍膨胀：1.6MB 原始字节 → 约 2.13M 字符 > 2 * 1024 * 1024
      final file = File('${tmp.path}/big.jpg')
        ..writeAsBytesSync(List<int>.filled(1600 * 1024, 1));
      expect(file.lengthSync(), greaterThan(0));
      await expectLater(
        AiChatImageFlow.toDataUrl(file),
        throwsA(isA<AiImageException>().having(
            (e) => e.message, 'message', contains('图片太大'))),
      );
    });

    test('空文件给出「读不出来」而不是崩溃', () async {
      final file = File('${tmp.path}/empty.jpg')..writeAsBytesSync(const []);
      await expectLater(
        AiChatImageFlow.toDataUrl(file),
        throwsA(isA<AiImageException>().having(
            (e) => e.message, 'message', contains('读不出来'))),
      );
    });

    test('buildUserPayload 把超限异常转成用户文案（不抛给 UI）', () async {
      final file = File('${tmp.path}/big2.jpg')
        ..writeAsBytesSync(List<int>.filled(1600 * 1024, 1));
      final result =
          await AiUserPayloadResult.load(text: '看图', image: file);
      expect(result.isOk, isFalse);
      expect(result.payload, isNull);
      expect(result.error, contains('图片太大'));
    });
  });

  group('复制按钮（widget）', () {
    final calls = <MethodCall>[];

    void mockClipboard() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
    }

    Future<void> pumpBubble(WidgetTester tester, Widget bubble) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: bubble)),
      ));
    }

    testWidgets('点助手气泡的复制按钮 → 写入剪贴板并提示「已复制」', (tester) async {
      calls.clear();
      mockClipboard();
      await pumpBubble(tester, const AiChatBubble.assistant(text: '今天练腿'));

      await tester.tap(find.text('复制'));
      await tester.pump();

      final copy =
          calls.where((c) => c.method == 'Clipboard.setData').toList();
      expect(copy, hasLength(1));
      expect((copy.single.arguments as Map)['text'], '今天练腿');
      expect(find.text('已复制'), findsOneWidget);
    });

    testWidgets('流式中 / 空内容不显示复制按钮', (tester) async {
      await pumpBubble(
        tester,
        const AiChatBubble.assistant(text: '', pending: true),
      );
      expect(find.text('复制'), findsNothing);

      await pumpBubble(
        tester,
        const AiChatBubble.assistant(text: '正文', canCopy: false),
      );
      expect(find.text('复制'), findsNothing);
    });

    testWidgets('用户气泡长按复制', (tester) async {
      calls.clear();
      mockClipboard();
      await pumpBubble(tester, const AiChatBubble.user(text: '160 斤'));

      await tester.longPress(find.text('160 斤'));
      await tester.pump();

      final copy =
          calls.where((c) => c.method == 'Clipboard.setData').toList();
      expect(copy, hasLength(1));
      expect((copy.single.arguments as Map)['text'], '160 斤');
      expect(find.text('已复制'), findsOneWidget);
      expect(find.text('复制'), findsNothing, reason: '用户气泡不显示复制按钮');
    });
  });
}
