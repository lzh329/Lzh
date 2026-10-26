import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

void main() {
  group('AiService.parseSseLine', () {
    test('普通增量行返回 content', () {
      const line =
          'data: {"choices":[{"delta":{"content":"今天"},"finish_reason":null}]}';
      expect(AiService.parseSseLine(line), '今天');
    });

    test('首帧（无 content）返回空串', () {
      const line = 'data: {"choices":[{"delta":{"role":"assistant"}}]}';
      expect(AiService.parseSseLine(line), '');
    });

    test('非 data 行返回 null', () {
      expect(AiService.parseSseLine('event: message'), isNull);
      expect(AiService.parseSseLine(''), isNull);
    });

    test('[DONE] 行由 isDoneLine 识别且 parse 返回 null', () {
      expect(AiService.isDoneLine('data: [DONE]'), isTrue);
      expect(AiService.parseSseLine('data: [DONE]'), isNull);
      expect(AiService.isDoneLine('data: {"choices":[]}'), isFalse);
    });

    test('坏 JSON 帧返回空串不抛异常', () {
      expect(AiService.parseSseLine('data: {oops'), '');
    });
  });

  group('AiService.resolveKey', () {
    test('设置里的 Key 去空格后生效', () {
      expect(AiService.resolveKey('  id-abc123  '), 'id-abc123');
    });

    test('空值返回 null', () {
      expect(AiService.resolveKey(null), isNull);
      expect(AiService.resolveKey('   '), isNull);
    });
  });

  group('AiPromptBuilder.build', () {
    test('空数据也能构建引导性 prompt', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('嘎教练'));
      expect(prompt, contains('暂无体重记录'));
      expect(prompt, contains('目标体重'));
    });

    test('注入体重 / 目标 / 训练等关键数据', () {
      final now = DateTime.now();
      final metrics = [
        BodyMetricEntity(id: 1, date: now, weightKg: 80, note: null),
        BodyMetricEntity(id: 2, date: now, weightKg: 75, note: null),
      ];
      final trends = TrendsData(
        metrics: metrics,
        targetJin: 140,
        workoutDays: 12,
        weekWorkoutCount: 3,
        weekWorkoutMinutes: 95,
        todayCups: 5,
        todayCalories: 1500,
      );
      const settings = UserSettingsEntity(
        id: 1,
        heightCm: 175,
        gender: 'male',
        birthDate: null,
      );
      final prompt = AiPromptBuilder.build(trends: trends, settings: settings);
      expect(prompt, contains('150.0 斤')); // 当前体重
      expect(prompt, contains('目标体重 140.0 斤'));
      expect(prompt, contains('累计减重 10.0 斤'));
      expect(prompt, contains('本周训练 3 次 / 约 95 分钟'));
      expect(prompt, contains('今日饮水 5 杯'));
      expect(prompt, contains('175cm'));
    });

    test('本周无训练时给出"还没有"提示', () {
      final prompt = AiPromptBuilder.build(
        trends: const TrendsData(),
        settings: null,
      );
      expect(prompt, contains('本周还没有训练记录'));
    });
  });

  group('AiCoachOptions', () {
    test('约束编解码往返一致', () {
      const items = ['别跟我客套', '  别提体重数字  '];
      final encoded = AiCoachOptions.encodeConstraints(items);
      expect(AiCoachOptions.decodeConstraints(encoded),
          ['别跟我客套', '别提体重数字']);
    });

    test('非法或空值返回空列表', () {
      expect(AiCoachOptions.decodeConstraints(null), isEmpty);
      expect(AiCoachOptions.decodeConstraints(''), isEmpty);
      expect(AiCoachOptions.decodeConstraints('not-json'), isEmpty);
      expect(AiCoachOptions.decodeConstraints('{"a":1}'), isEmpty);
    });

    test('未知风格/长度回落到默认档', () {
      expect(AiCoachOptions.styleOf('unknown').key, 'guga');
      expect(AiCoachOptions.styleOf(null).key, 'guga');
      expect(AiCoachOptions.lengthOf('unknown').key, 'medium');
    });
  });

  group('AiPromptBuilder 调教设定', () {
    test('自定义约束写进提示词且编号', () {
      final settings = UserSettingsEntity(
        id: 1,
        aiConstraints:
            AiCoachOptions.encodeConstraints(['别跟我客套', '别提体重数字']),
      );
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, contains('用户额外约束'));
      expect(prompt, contains('1. 别跟我客套'));
      expect(prompt, contains('2. 别提体重数字'));
    });

    test('严厉风格替换默认人设', () {
      const settings = UserSettingsEntity(id: 1, aiStyle: 'strict');
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, contains('零废话'));
      expect(prompt, isNot(contains('东北式幽默')));
    });

    test('简短长度写入对应字数限制', () {
      const settings = UserSettingsEntity(id: 1, aiReplyLength: 'short');
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, contains('80 字以内'));
    });

    test('四种基础规则都在（防编造/医疗/极端节食/不用 Markdown）', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('绝不编造'));
      expect(prompt, contains('不做医疗诊断'));
      expect(prompt, contains('1200 千卡'));
      expect(prompt, contains('不用 Markdown'));
    });
  });

  group('AiToolArgs 参数校验', () {
    test('体重斤 → 公斤，且限制 40~600 斤', () {
      expect(AiToolArgs.weightKg({'weight_jin': 160}), 80);
      expect(AiToolArgs.weightJin({'weight_jin': 161.0}), 161.0);
      expect(() => AiToolArgs.weightKg({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.weightKg({'weight_jin': 10}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.weightKg({'weight_jin': 800}),
          throwsA(isA<AiToolException>()));
    });

    test('杯数限制 1~30', () {
      expect(AiToolArgs.cups({'cups': 6}), 6);
      expect(() => AiToolArgs.cups({'cups': 0}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.cups({'cups': 50}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.cups({}), throwsA(isA<AiToolException>()));
    });

    test('日期默认今天、拒绝未来与过久', () {
      final today = DateTime.now();
      final d = AiToolArgs.date({});
      expect(d.day, DateTime(today.year, today.month, today.day).day);

      expect(
          () => AiToolArgs.date(
              {'date': today.add(const Duration(days: 1)).toIso8601String()}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.date({'date': 'not-a-date'}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.date(
              {'date': today.subtract(const Duration(days: 400)).toIso8601String()}),
          throwsA(isA<AiToolException>()));
    });

    test('统计范围非法值回落到 week', () {
      expect(AiToolArgs.range({'range': 'month'}), 'month');
      expect(AiToolArgs.range({'range': 'xx'}), 'week');
      expect(AiToolArgs.range({}), 'week');
    });

    test('饮食参数：名称/克数/热量校验', () {
      expect(AiToolArgs.foodName({'food_name': ' 牛肉面 '}), '牛肉面');
      expect(() => AiToolArgs.foodName({}), throwsA(isA<AiToolException>()));
      expect(AiToolArgs.grams({'grams': 250}), 250);
      expect(() => AiToolArgs.grams({'grams': 0}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.grams({'grams': 5000}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.caloriesPer100g({'calories_per_100g': 116}), 116);
      expect(() => AiToolArgs.caloriesPer100g({'calories_per_100g': 2000}),
          throwsA(isA<AiToolException>()));
    });

    test('餐次非法值按时间推断，且必为四选一', () {
      expect(AiToolArgs.mealType({'meal_type': 'lunch'}), 'lunch');
      const valid = ['breakfast', 'lunch', 'dinner', 'snack'];
      expect(valid.contains(AiToolArgs.mealType({'meal_type': 'xx'})), isTrue);
      expect(valid.contains(AiToolArgs.mealType({})), isTrue);
    });

    test('训练参数：类型归一化与时长校验', () {
      expect(AiToolArgs.workoutType({'workout_type': '有氧'}), '有氧');
      expect(AiToolArgs.workoutType({'workout_type': 'strength'}), '力量');
      expect(AiToolArgs.workoutType({'workout_type': 'unknown'}), '其他');
      expect(AiToolArgs.minutes({'minutes': 30}), 30);
      expect(() => AiToolArgs.minutes({'minutes': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.minutes({'minutes': 999}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.workoutNote({'note': '  深蹲 4×12  '}), '深蹲 4×12');
      expect(AiToolArgs.workoutNote({}), isNull);
    });
  });

  group('parseToolCallDelta', () {
    test('解析首片（id + name）', () {
      const line =
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"log_weight","arguments":""}}]}}]}';
      final d = AiService.parseToolCallDelta(line);
      expect(d, isNotNull);
      expect(d!.id, 'call_1');
      expect(d.name, 'log_weight');
    });

    test('解析参数分片', () {
      const line =
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"weight_jin\\":161}"}}]}}]}';
      final d = AiService.parseToolCallDelta(line);
      expect(d!.arguments, '{"weight_jin":161}');
      expect(d.name, isNull);
    });

    test('普通内容帧返回 null', () {
      expect(
          AiService.parseToolCallDelta(
              'data: {"choices":[{"delta":{"content":"hi"}}]}'),
          isNull);
      expect(AiService.parseToolCallDelta('data: [DONE]'), isNull);
    });
  });

  group('streamChat 工具调用（mock 流式响应）', () {
    test('分片工具调用被拼接成完整调用，且请求带上 tools', () async {
      late String requestBody;
      final client = MockClient.streaming((request, bodyStream) async {
        requestBody = await bodyStream.bytesToString();
        final chunks = [
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"log_weight","arguments":""}}]}}]}\n\n',
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"weight_jin\\":160}"}}]}}]}\n\n',
          'data: [DONE]\n\n',
        ];
        return http.StreamedResponse(
            Stream.fromIterable(chunks.map(utf8.encode)), 200);
      });

      final result = await AiService.streamChat(
        apiKey: 'test-key',
        messages: const [AiMessage(role: 'user', content: '160 斤')],
        tools: AiToolSpecs.defs,
        onDelta: (_) {},
        client: client,
      );

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.first.id, 'call_1');
      expect(result.toolCalls.first.name, 'log_weight');
      expect(result.toolCalls.first.arguments['weight_jin'], 160);
      expect(requestBody, contains('"tools"'));
      expect(requestBody, contains('"tool_choice":"auto"'));
    });

    test('普通文本流式回复正常返回', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final chunks = [
          'data: {"choices":[{"delta":{"content":"今天"}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"练腿"}}]}\n\n',
          'data: [DONE]\n\n',
        ];
        return http.StreamedResponse(
            Stream.fromIterable(chunks.map(utf8.encode)), 200);
      });

      final deltas = <String>[];
      final result = await AiService.streamChat(
        apiKey: 'test-key',
        messages: const [AiMessage(role: 'user', content: '练什么')],
        onDelta: deltas.add,
        client: client,
      );
      expect(result.content, '今天练腿');
      expect(result.toolCalls, isEmpty);
      expect(deltas.join(), '今天练腿');
    });
  });
}
