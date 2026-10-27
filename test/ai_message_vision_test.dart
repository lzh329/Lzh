import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_tool_context.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// v1.4：AI 接口 400 修复 / 图片消息 / 提示词去死板的纯逻辑测试
/// （不连数据库、不调网络）
void main() {
  group('AiMessage.toJson', () {
    test('普通文本消息原样输出，content 仍是字符串', () {
      const msg = AiMessage(role: 'user', content: '今天怎么练？');
      final json = msg.toJson();
      expect(json['role'], 'user');
      expect(json['content'], '今天怎么练？');
      expect(json.containsKey('tool_calls'), isFalse);
      expect(json.containsKey('tool_call_id'), isFalse);
      expect(json.containsKey('name'), isFalse);
    });

    test('带 tool_calls 且无正文时 content 为 null（不是空串）', () {
      const msg = AiMessage(
        role: 'assistant',
        content: '',
        toolCalls: [
          AiToolCall(
            id: 'call_1',
            name: 'log_weight',
            argumentsJson: '{"weight_jin":160}',
          ),
        ],
      );
      final json = msg.toJson();
      expect(json.containsKey('content'), isTrue);
      expect(json['content'], isNull);
      final calls = json['tool_calls'] as List;
      expect(calls, hasLength(1));
      final call = calls.first as Map<String, dynamic>;
      expect(call['id'], 'call_1');
      expect(call['type'], 'function');
      expect((call['function'] as Map)['name'], 'log_weight');
    });

    test('既有正文又有 tool_calls 时 content 保留正文', () {
      const msg = AiMessage(
        role: 'assistant',
        content: '我记一下',
        toolCalls: [
          AiToolCall(id: 'call_2', name: 'log_water', argumentsJson: '{}'),
        ],
      );
      final json = msg.toJson();
      expect(json['content'], '我记一下');
      expect((json['tool_calls'] as List), hasLength(1));
    });

    test('tool 消息带 tool_call_id 与 name', () {
      const msg = AiMessage(
        role: 'tool',
        content: '{"ok":true}',
        toolCallId: 'call_1',
        toolName: 'log_weight',
      );
      final json = msg.toJson();
      expect(json['role'], 'tool');
      expect(json['content'], '{"ok":true}');
      expect(json['tool_call_id'], 'call_1');
      expect(json['name'], 'log_weight');
    });

    test('多模态消息 content 原样透传（数组）', () {
      final content = AiChatImageFlow.buildContent(
        text: '这碗面多少热量',
        dataUrl: 'data:image/jpeg;base64,AAAA',
      );
      final msg = AiMessage(role: 'user', content: content);
      final json = msg.toJson();
      final parts = json['content'] as List;
      expect(parts, hasLength(2));
      expect((parts.first as Map)['type'], 'text');
      expect((parts.first as Map)['text'], '这碗面多少热量');
      final image = parts.last as Map;
      expect(image['type'], 'image_url');
      expect((image['image_url'] as Map)['url'], startsWith('data:image'));
    });
  });

  group('AiMessage.textOnly', () {
    test('字符串消息直接返回', () {
      expect(const AiMessage(role: 'user', content: '你好').textOnly, '你好');
    });

    test('图片消息只取文字段（用于气泡与复制）', () {
      final msg = AiMessage(
        role: 'user',
        content: AiChatImageFlow.buildContent(
          text: ' 午饭 ',
          dataUrl: 'data:image/jpeg;base64,AAAA',
        ),
      );
      expect(msg.textOnly, '午饭');
    });
  });

  group('AiChatImageFlow', () {
    test('buildContent：有文字用文字，没文字补默认提问', () {
      final withText = AiChatImageFlow.buildContent(
        text: '  晚饭吃了这些  ',
        dataUrl: 'data:image/jpeg;base64,AA',
      );
      expect((withText.first)['text'], '晚饭吃了这些');

      final withoutText = AiChatImageFlow.buildContent(
        text: '   ',
        dataUrl: 'data:image/jpeg;base64,AA',
      );
      expect((withoutText.first)['text'], AiChatImageFlow.defaultText);
      expect((withoutText.last)['type'], 'image_url');
    });

    test('historyText：数据库只存文本，图片用 [图片] 占位', () {
      expect(AiChatImageFlow.historyText('牛肉面'), '牛肉面 [图片]');
      expect(AiChatImageFlow.historyText('  '), '[图片]');
    });

    test('2MB 上限：等于上限不算超，超 1 个字符就算超', () {
      final atLimit = 'a' * AiChatImageFlow.maxBase64Chars;
      expect(AiChatImageFlow.isOversize(atLimit), isFalse);
      expect(AiChatImageFlow.isOversize('${atLimit}a'), isTrue);
    });
  });

  group('工具 schema（400 修复）', () {
    test('不存在空的 required 数组', () {
      for (final def in AiToolSpecs.defs) {
        final fn = def['function'] as Map;
        final params = fn['parameters'] as Map;
        if (params.containsKey('required')) {
          expect(params['required'] as List, isNotEmpty,
              reason: '${fn['name']} 不该出现 "required": []');
        }
      }
    });

    test('没必填参数的工具（围度/身体信息/饮食目标/查动作）确实没写 required', () {
      const optionalArgTools = [
        AiToolSpecs.logMeasurements,
        AiToolSpecs.updateProfile,
        AiToolSpecs.setDietTarget,
        AiToolSpecs.queryExercises,
      ];
      for (final name in optionalArgTools) {
        final def = AiToolSpecs.defs
            .firstWhere((d) => (d['function'] as Map)['name'] == name);
        final params = (def['function'] as Map)['parameters'] as Map;
        expect(params.containsKey('required'), isFalse,
            reason: '$name 不应带 required 键');
      }
    });

    test('有必填参数的工具 required 仍然保留', () {
      final def = AiToolSpecs.defs.firstWhere(
          (d) => (d['function'] as Map)['name'] == AiToolSpecs.logWeight);
      final params = (def['function'] as Map)['parameters'] as Map;
      expect(params['required'], ['weight_jin']);
    });
  });

  group('提示词：说话方式与弹性格式', () {
    final defaultPrompt =
        AiPromptBuilder.build(trends: const TrendsData(), settings: null);

    test('四种风格都写了「说话方式」', () {
      expect(AiCoachOptions.styles, hasLength(4));
      for (final style in AiCoachOptions.styles) {
        final joined = style.personaLines.join('\n');
        expect(joined, contains('说话方式'), reason: '${style.key} 缺少说话方式');
      }
      expect(defaultPrompt, contains('说话方式'));
    });

    test('嘎式：允许语气词与 emoji，且要求换开头', () {
      final guga = AiCoachOptions.styleOf('guga').personaLines.join('\n');
      expect(guga, contains('嘿'));
      expect(guga, contains('emoji'));
      expect(guga, contains('开头'));
      expect(guga, contains('自嘲'));
    });

    test('温柔风：多用「我们」；严厉风：短句 + 一句犀利判断', () {
      final gentle = AiCoachOptions.styleOf('gentle').personaLines.join('\n');
      expect(gentle, contains('我们'));
      expect(gentle, contains('情绪'));

      final strict = AiCoachOptions.styleOf('strict').personaLines.join('\n');
      expect(strict, contains('短句'));
      expect(strict, contains('犀利'));
      expect(strict, contains('不针对人'));
    });

    test('输出格式有弹性：口语为主，不套模板', () {
      // 默认（豆包感）走「像发微信」的口径
      expect(defaultPrompt, contains('有弹性'));
      expect(defaultPrompt, contains('1~3 句'));
      expect(defaultPrompt, contains('不主动分点'));
      expect(defaultPrompt, contains('不要每条都用相同模板开头'));
      expect(defaultPrompt, contains('不要连续两条回复都用分点列表'));
      // 不再强制「结尾必须给动作」
      expect(defaultPrompt, isNot(contains('结尾必须给 1 个今天就能执行的动作')));

      // 老风格仍保留弹性长度档位逻辑（2~4 句、不强求分点）
      const gugaSettings = UserSettingsEntity(id: 1, aiStyle: 'guga');
      final gugaPrompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: gugaSettings);
      expect(gugaPrompt, contains('有弹性'));
      expect(gugaPrompt, contains('2~4 句'));
      expect(gugaPrompt, contains('不强求分点'));
      expect(gugaPrompt, contains('先顺一下对方的话'),
          reason: '不再机械地"第一句直接给结论"');
      expect(gugaPrompt, isNot(contains('结尾必须给 1 个今天就能执行的动作')));
    });

    test('保留不用 Markdown，但允许「·」列表与空行分段', () {
      expect(defaultPrompt, contains('不用 Markdown'));
      expect(defaultPrompt, contains('"·"'));
      expect(defaultPrompt, contains('空行'));
    });

    test('视觉引导：食物照片先估分量再记', () {
      expect(defaultPrompt, contains('用户发食物照片时'));
      expect(defaultPrompt, contains('log_food'));
    });

    test('安全边界没被削弱', () {
      expect(defaultPrompt, contains('绝不编造'));
      expect(defaultPrompt, contains('不做医疗诊断'));
      expect(defaultPrompt, contains('不承诺减重速度'));
      expect(defaultPrompt, contains('1200 千卡'));
    });
  });

  group('默认温度', () {
    test('默认值调高到 0.9（设置页仍可调）', () {
      expect(AiService.defaultTemperature, 0.9);
    });
  });

  group('thinking 模式（工具回合 400 的根因）', () {
    test('请求固定关闭 thinking：不需要回传 reasoning_content', () {
      expect(AiService.disabledThinking, {'type': 'disabled'});
    });

    test('工具回合的消息体逐条合规（content=null / name / tool_call_id）', () {
      final ctx = AiToolContext();
      ctx.append(
        const AiToolCall(
          id: 'call_9',
          name: 'log_weight',
          argumentsJson: '{"weight_jin":160}',
        ),
        '{"ok":true}',
      );
      final body = [
        const AiMessage(role: 'system', content: 'sys'),
        const AiMessage(role: 'user', content: '160 斤'),
        ...ctx.messages,
      ].map((m) => m.toJson()).toList();

      expect(body, hasLength(4));
      // assistant 工具调用消息：content 必须是 null
      expect(body[2]['role'], 'assistant');
      expect(body[2]['content'], isNull);
      expect(body[2]['tool_calls'], isA<List>());
      // tool 结果消息：必须带 name + tool_call_id
      expect(body[3]['role'], 'tool');
      expect(body[3]['tool_call_id'], 'call_9');
      expect(body[3]['name'], 'log_weight');
      expect(body[3]['content'], '{"ok":true}');
    });
  });

  group('AiService 错误文案（服务端 message 并入）', () {
    test('解析 error.message', () {
      const body = '{"error":{"message":"Model Not Exist","type":"invalid"}}';
      expect(AiService.extractServerMessage(body), 'Model Not Exist');
    });

    test('非 JSON / 空响应体返回 null', () {
      expect(AiService.extractServerMessage(''), isNull);
      expect(AiService.extractServerMessage('<html>502</html>'), isNull);
      expect(AiService.extractServerMessage('{"error":{}}'), isNull);
    });

    test('超长文案截断到 60 字', () {
      final long = 'x' * 200;
      expect(AiService.truncate(long, AiService.serverMessageMaxChars).length,
          AiService.serverMessageMaxChars + 1); // 含省略号
      expect(AiService.truncate('短文案', 60), '短文案');
    });
  });
}
