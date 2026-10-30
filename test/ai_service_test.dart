import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'fake_database.dart';
import 'package:fittrack/features/ai/data/ai_tool_admin_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_body_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/data/ai_tool_library_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_readers.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/data/ai_tool_settings_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_web_readers.dart';
import 'package:fittrack/features/ai/data/ai_tool_workout_launcher.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/entities/diet_entity.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';

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
    test('明确声明视觉能力，避免模型自认不能识图', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('# 你能做什么'));
      expect(prompt, contains('你能直接看图'));
      expect(prompt, contains('你能识图吗'));
      expect(prompt, contains('食物照片'));
    });

    test('空数据也能构建引导性 prompt', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('嘎教练'));
      expect(prompt, contains('暂无体重记录'));
      expect(prompt, contains('目标体重'));
    });

    test('联网与工具规则：调用即执行、结果即答案（不做空承诺）', () {
      // 联网默认开启（settings null = 按开启处理），应带「立刻调用」的硬规则
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('调用即执行、结果即答案'));
      expect(prompt, contains('立刻在这一次回复里调用 web_search'));
      expect(prompt, contains('完整答案一次说完'));
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
      expect(AiCoachOptions.decodeConstraints(encoded), ['别跟我客套', '别提体重数字']);
    });

    test('非法或空值返回空列表', () {
      expect(AiCoachOptions.decodeConstraints(null), isEmpty);
      expect(AiCoachOptions.decodeConstraints(''), isEmpty);
      expect(AiCoachOptions.decodeConstraints('not-json'), isEmpty);
      expect(AiCoachOptions.decodeConstraints('{"a":1}'), isEmpty);
    });

    test('未知风格/长度回落到默认档（默认 = 豆包感）', () {
      expect(AiCoachOptions.styleOf('unknown').key, 'doubao');
      expect(AiCoachOptions.styleOf(null).key, 'doubao');
      expect(AiCoachOptions.styleOf('').key, 'doubao');
      expect(AiCoachOptions.lengthOf('unknown').key, 'medium');
      expect(AiCoachOptions.lengthOf(null).key, 'medium');
    });

    test('四种风格 key 唯一，且豆包感排第一位（默认位）', () {
      expect(AiCoachOptions.styles, hasLength(4));
      final keys = AiCoachOptions.styles.map((s) => s.key).toList();
      expect(keys.toSet(), hasLength(4), reason: '风格 key 必须唯一');
      expect(keys, ['doubao', 'guga', 'gentle', 'strict']);
      expect(AiCoachOptions.styles.first.key, 'doubao',
          reason: 'styles.first 就是 styleOf 的回落目标');
      // 老三种风格仍然可以精确取到，不会被新默认吃掉
      expect(AiCoachOptions.styleOf('guga').label, '嘎式默认');
      expect(AiCoachOptions.styleOf('gentle').label, '温柔学姐');
      expect(AiCoachOptions.styleOf('strict').label, '严厉硬核');
      expect(AiCoachOptions.styleOf('doubao').label, '豆包感');
      // 每张卡片的文案都不为空、长度可控（设置页不溢出）
      for (final s in AiCoachOptions.styles) {
        expect(s.description, isNotEmpty);
        expect(s.description.length, lessThanOrEqualTo(24),
            reason: '${s.key} 的 description 太长，设置页卡片会换行过多');
      }
    });
  });

  group('AiPromptBuilder 调教设定', () {
    test('自定义约束写进提示词且编号', () {
      final settings = UserSettingsEntity(
        id: 1,
        aiConstraints: AiCoachOptions.encodeConstraints(['别跟我客套', '别提体重数字']),
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

    test('简短长度写入对应字数限制（非豆包风格走档位逻辑）', () {
      const settings =
          UserSettingsEntity(id: 1, aiStyle: 'guga', aiReplyLength: 'short');
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, contains('80 字以内'));
    });

    test('豆包风格不吃档位文案，只把档位当参考', () {
      const settings =
          UserSettingsEntity(id: 1, aiStyle: 'doubao', aiReplyLength: 'short');
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, contains('100 字'));
      expect(prompt, contains('「简短」'), reason: '档位仍作为偏好提示给模型');
      expect(prompt, isNot(contains('80 字以内')),
          reason: '豆包风格以 1~3 句 / 100 字为准，不再叠旧档位文案');
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

  // ═════════════ v1.5：豆包感（像朋友聊天，不像教练上课） ═════════════

  group('豆包感提示词', () {
    final defaultPrompt =
        AiPromptBuilder.build(trends: const TrendsData(), settings: null);

    test('默认风格就是豆包感（没存过设置的用户直接生效）', () {
      expect(defaultPrompt, contains('豆包那种感觉'));
      expect(defaultPrompt, contains('嘎教练'));
      expect(defaultPrompt, isNot(contains('东北式幽默')), reason: '默认不该再是嘎式人设');
    });

    test('人设关键词：语气词 / 追问 / 不长篇 / 先接情绪', () {
      final doubao = AiCoachOptions.styleOf('doubao').personaLines.join('\n');
      expect(doubao, contains('语气词'));
      expect(doubao, contains('追问'));
      expect(doubao, contains('短句'));
      expect(doubao, contains('不默认列清单'));
      expect(doubao, contains('先接住'));
      expect(doubao, contains('说话方式'));
      // 明确反对书面腔与教学腔
      expect(doubao, contains('建议您'));
      expect(doubao, contains('需要注意的是'));
      expect(doubao, contains('综上所述'));
      expect(doubao, contains('emoji'));
    });

    test('输出格式：1~3 句 / 100 字，且不主动分点', () {
      expect(defaultPrompt, contains('1~3 句'));
      expect(defaultPrompt, contains('100 字'));
      expect(defaultPrompt, contains('不主动分点'));
      expect(defaultPrompt, contains('追问一句'));
      expect(defaultPrompt, contains('3 条以内'), reason: '只有要计划时才列点，且 ≤3 条');
    });

    test('不再硬塞「结论 + 要点 + 动作」，也不强制结尾给动作', () {
      expect(defaultPrompt, isNot(contains('结尾必须给 1 个今天就能执行的动作')));
      expect(defaultPrompt, isNot(contains('第一句直接给结论')));
    });

    test('few-shot 三组示例（闲聊 / 数据 / 记录），emoji 不超过 1 个', () {
      expect(defaultPrompt, contains('用户：今天好累啊，不想动。'));
      expect(defaultPrompt, contains('用户：我这周是不是很废？'));
      expect(defaultPrompt, contains('用户：刚吃了碗牛肉面。'));
      // 三个示例合计最多 1 个 emoji（克制，不刷屏）
      final exampleStart = defaultPrompt.indexOf('# 示例');
      final exampleBlock = defaultPrompt.substring(
          exampleStart, defaultPrompt.indexOf('# 用户数据'));
      final emojiCount =
          RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true)
              .allMatches(exampleBlock)
              .length;
      expect(emojiCount, lessThanOrEqualTo(1));
      // 情绪类示例不列点（对话型只用短句，不用「·」）
      final chatExample = exampleBlock.substring(
          exampleBlock.indexOf('今天好累啊'), exampleBlock.indexOf('【示例 2'));
      expect(chatExample, isNot(contains('· ')));
      // 示例只是语气示范，数字以真实数据为准
      expect(defaultPrompt, contains('真实数据一律以【用户数据】为准'));
    });

    test('安全边界四条仍在，工具规则未被破坏', () {
      expect(defaultPrompt, contains('绝不编造'));
      expect(defaultPrompt, contains('不做医疗诊断'));
      expect(defaultPrompt, contains('不承诺减重速度'));
      expect(defaultPrompt, contains('1200 千卡'));
      // 17 工具相关约定照旧
      expect(defaultPrompt, contains('set_target_weight'));
      expect(defaultPrompt, contains('manage_goal(action:create)'));
      expect(defaultPrompt, contains('不要凭猜的 id'));
      expect(defaultPrompt, contains('建训练模板前先用 query_exercises 确认动作存在'));
      expect(defaultPrompt, contains('先 create_exercise 加进动作库'));
      expect(defaultPrompt, contains('帮我加个动作'));
      expect(defaultPrompt, contains('create_missing_exercises'));
      expect(defaultPrompt, contains('create_exercises'));
      expect(defaultPrompt, contains('不要逐个调用工具'));
      expect(defaultPrompt, contains('先一句话说明后果'));
      expect(defaultPrompt, contains('用户发食物照片时'));
      expect(defaultPrompt, contains('${AiToolLimits.maxCallsPerRound} 次工具调用'));
      expect(defaultPrompt, contains('log_food'));
      expect(defaultPrompt, contains('query_stats'));
    });

    test('去播报腔，但不复述用户问题这条要求保留', () {
      expect(defaultPrompt, contains('根据你的数据'));
      expect(defaultPrompt, contains('播报腔'));
      expect(defaultPrompt, contains('也不用把用户的话再复述一遍'));
    });

    test('自定义约束优先级仍在最后注入', () {
      final settings = UserSettingsEntity(
        id: 1,
        aiConstraints: AiCoachOptions.encodeConstraints(['别跟我客套']),
      );
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt.indexOf('# 用户额外约束') > prompt.indexOf('# 用户数据'), isTrue,
          reason: '自定义约束必须放在最后，模型才更容易遵守');
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
      expect(
          () => AiToolArgs.cups({'cups': 0}), throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.cups({'cups': 50}), throwsA(isA<AiToolException>()));
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
      expect(() => AiToolArgs.date({'date': 'not-a-date'}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.date({
                'date':
                    today.subtract(const Duration(days: 400)).toIso8601String()
              }),
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
      expect(() => AiToolArgs.grams({'grams': 0}),
          throwsA(isA<AiToolException>()));
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
      // thinking 必须关掉：它要求每轮回传 reasoning_content，否则工具回合 400
      expect(requestBody, contains('"thinking":{"type":"disabled"}'));
      final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
      expect(decoded['thinking'], {'type': 'disabled'});
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

  // ═════════════ v1.3 新增 8 个工具（纯参数校验，不碰数据库） ═════════════

  group('log_measurements 参数校验', () {
    test('至少一项 + 各字段 30~200cm', () {
      final m = AiToolArgs.measurements({'waist_cm': 80, 'hip_cm': 95.5});
      expect(m.waistCm, 80);
      expect(m.hipCm, 95.5);
      expect(m.chestCm, isNull);
      expect(m.label, '腰围 80cm · 臀围 95.5cm');

      expect(
          () => AiToolArgs.measurements({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.measurements({'waist_cm': 10}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.measurements({'chest_cm': 250}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.measurements({'hip_cm': 'abc'}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.measurements({'waist_cm': 30}).waistCm, 30);
      expect(AiToolArgs.measurements({'waist_cm': 200}).waistCm, 200);
    });

    test('体重可选：缺失为 null，给了就校验 40~600 斤', () {
      expect(AiToolArgs.optionalWeightKg({}), isNull);
      expect(AiToolArgs.optionalWeightKg({'weight_jin': 161}), 80.5);
      expect(() => AiToolArgs.optionalWeightKg({'weight_jin': 10}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.optionalWeightKg({'weight_jin': 700}),
          throwsA(isA<AiToolException>()));
    });
  });

  group('set_target_weight 参数校验', () {
    test('目标体重按斤校验 40~600', () {
      expect(AiToolArgs.targetWeightKg({'target_jin': 140}), 70);
      expect(AiToolArgs.targetWeightKg({'target_jin': 40}), 20);
      expect(AiToolArgs.targetWeightKg({'target_jin': 600}), 300);
      expect(() => AiToolArgs.targetWeightKg({'target_jin': 30}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.targetWeightKg({'target_jin': 800}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.targetWeightKg({}), throwsA(isA<AiToolException>()));
      // 字段名是 target_jin，不能误读 weight_jin
      expect(() => AiToolArgs.targetWeightKg({'weight_jin': 140}),
          throwsA(isA<AiToolException>()));
    });
  });

  group('update_profile 参数校验', () {
    test('至少一项 + 身高 100~250 + 性别枚举 + 出生年范围', () {
      final p = AiToolArgs.profile(
          {'height_cm': 175, 'gender': 'male', 'birth_year': 1995});
      expect(p.heightCm, 175);
      expect(p.gender, 'male');
      expect(p.birthYear, 1995);
      expect(p.label, '身高 175cm · 男 · 1995 年生');

      expect(() => AiToolArgs.profile({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'height_cm': 90}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'height_cm': 300}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'gender': 'x'}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'birth_year': 1900}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'birth_year': DateTime.now().year - 5}),
          throwsA(isA<AiToolException>()));
      // 单独给性别也能过
      expect(AiToolArgs.profile({'gender': 'female'}).gender, 'female');
    });
  });

  group('set_diet_target 参数校验', () {
    test('至少一项 + 热量 800~5000 + 宏量 0~500', () {
      final t = AiToolArgs.dietTarget({'calories': 1800, 'protein_g': 120});
      expect(t.calories, 1800);
      expect(t.proteinG, 120);
      expect(t.carbsG, isNull);
      expect(t.label, '每日 1800 千卡 · 蛋白 120g');

      expect(AiToolArgs.dietTarget({'calories': 800}).calories, 800);
      expect(AiToolArgs.dietTarget({'calories': 5000}).calories, 5000);
      expect(AiToolArgs.dietTarget({'fat_g': 0}).fatG, 0);
      expect(AiToolArgs.dietTarget({'carbs_g': 500}).carbsG, 500);

      expect(() => AiToolArgs.dietTarget({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'calories': 700}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'calories': 6000}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'protein_g': 600}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'carbs_g': -1}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'fat_g': 501}),
          throwsA(isA<AiToolException>()));
    });
  });

  group('set_reminder 参数校验', () {
    test('enabled 布尔解析（bool / 字符串 / 数字）', () {
      expect(AiToolArgs.boolArg({'enabled': true}, 'enabled', '提醒'), isTrue);
      expect(AiToolArgs.boolArg({'enabled': false}, 'enabled', '提醒'), isFalse);
      expect(AiToolArgs.boolArg({'enabled': 'true'}, 'enabled', '提醒'), isTrue);
      expect(
          AiToolArgs.boolArg({'enabled': ' FALSE '}, 'enabled', '提醒'), isFalse);
      expect(AiToolArgs.boolArg({'enabled': 1}, 'enabled', '提醒'), isTrue);
      expect(AiToolArgs.boolArg({'enabled': 0}, 'enabled', '提醒'), isFalse);
      expect(AiToolArgs.boolOf('maybe'), isNull);
      expect(() => AiToolArgs.boolArg({}, 'enabled', '提醒'),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.boolArg({'enabled': 'maybe'}, 'enabled', '提醒'),
          throwsA(isA<AiToolException>()));
    });

    test('小时 0~23、分钟 0~59，缺失为 null', () {
      expect(AiToolArgs.optionalHour({}), isNull);
      expect(AiToolArgs.optionalHour({'hour': 9}), 9);
      expect(AiToolArgs.optionalHour({'hour': 0}), 0);
      expect(AiToolArgs.optionalHour({'hour': 23}), 23);
      expect(AiToolArgs.optionalMinute({'minute': 0}), 0);
      expect(AiToolArgs.optionalMinute({'minute': 59}), 59);
      expect(() => AiToolArgs.optionalHour({'hour': 24}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.optionalMinute({'minute': 60}),
          throwsA(isA<AiToolException>()));
    });
  });

  group('delete_records 参数校验与危险标记', () {
    test('记录类型枚举（大小写不敏感）', () {
      for (final t in ['weight', 'food', 'workout', 'water']) {
        expect(AiToolArgs.recordType({'type': t}), t);
      }
      expect(AiToolArgs.recordType({'type': ' WEIGHT '}), 'weight');
      expect(() => AiToolArgs.recordType({'type': 'sleep'}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.recordType({}), throwsA(isA<AiToolException>()));
    });

    test('危险工具有两个：delete_records + wipe_all_data', () {
      expect(AiToolSpecs.destructiveTools, contains(AiToolSpecs.deleteRecords));
      expect(AiToolSpecs.destructiveTools, contains(AiToolSpecs.wipeAllData));
      expect(AiToolSpecs.destructiveTools,
          contains(AiToolSpecs.deleteMeasurement));
      expect(AiToolSpecs.destructiveTools, hasLength(3));
      expect(AiToolSpecs.isDestructive(AiToolSpecs.deleteRecords), isTrue);
      expect(AiToolSpecs.isDestructive(AiToolSpecs.logWeight), isFalse);
      expect(AiToolSpecs.isDestructive(AiToolSpecs.manageGoal), isFalse);
    });

    test('空记录提示按类型区分', () {
      expect(AiRecordTypes.emptyOf('food').message, contains('饮食'));
      expect(AiRecordTypes.emptyOf('water').message, contains('饮水'));
      expect(AiRecordTypes.labelOf('workout'), '训练');
    });
  });

  group('manage_goal 参数校验', () {
    test('action 枚举', () {
      expect(AiToolArgs.goalAction({'action': 'create'}), 'create');
      expect(AiToolArgs.goalAction({'action': 'Complete'}), 'complete');
      expect(AiToolArgs.goalAction({'action': 'delete'}), 'delete');
      expect(() => AiToolArgs.goalAction({'action': 'update'}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalAction({}), throwsA(isA<AiToolException>()));
    });

    test('complete / delete 需要正整数 goal_id', () {
      expect(AiToolArgs.goalId({'goal_id': 3}), 3);
      expect(AiToolArgs.goalId({'goal_id': '3'}), 3);
      expect(() => AiToolArgs.goalId({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalId({'goal_id': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalId({'goal_id': -2}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalId({'goal_id': 'abc'}),
          throwsA(isA<AiToolException>()));
    });

    test('goal_id 严格整数：3.7 抛异常，不静默截断', () {
      // 整数写法正常
      expect(AiToolArgs.intOf(3), 3);
      expect(AiToolArgs.intOf(3.0), 3);
      expect(AiToolArgs.intOf('3'), 3);
      expect(AiToolArgs.intOf('3.0'), 3);
      expect(AiToolArgs.intOf('abc'), isNull);
      // 带小数：抛异常，绝不能静默变成 3
      expect(() => AiToolArgs.intOf(3.7), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.intOf('3.7'), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalId({'goal_id': 3.7}),
          throwsA(isA<AiToolException>()));
      // 其他数值参数保持旧的宽松行为（截断），不受影响
      expect(AiToolArgs.cups({'cups': 3.7}), 3);
      expect(AiToolArgs.minutes({'minutes': 30.5}), 30);
    });

    test('create 需要类型 + 正的目标值，可选分类与结束日期', () {
      expect(AiToolArgs.goalType({'type': 'weight'}), 'weight');
      expect(AiToolArgs.goalType({'type': 'FREQUENCY'}), 'frequency');
      expect(() => AiToolArgs.goalType({'type': 'steps'}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.goalTargetValue({'target_value': 140}), 140);
      expect(() => AiToolArgs.goalTargetValue({'target_value': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalTargetValue({}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.goalCategory({'category': ' 瘦肚子 '}), '瘦肚子');
      expect(AiToolArgs.goalCategory({}), isNull);
      expect(AiToolArgs.goalEndDate({'end_date': '2026-03-01'}),
          DateTime(2026, 3, 1));
      expect(AiToolArgs.goalEndDate({}), isNull);
      expect(() => AiToolArgs.goalEndDate({'end_date': 'bad'}),
          throwsA(isA<AiToolException>()));
    });

    test('确认文案：create 带单位，complete/delete 带 id', () {
      const weight =
          AiGoalCommand(action: 'create', type: 'weight', targetValue: 140);
      expect(weight.createDetail, '新建体重目标：140 斤');
      const freq =
          AiGoalCommand(action: 'create', type: 'frequency', targetValue: 3);
      expect(freq.createDetail, '新建训练频率目标：3 次');
      const custom =
          AiGoalCommand(action: 'create', type: 'custom', targetValue: 12.5);
      expect(custom.createDetail, '新建自定义目标：12.5');
    });
  });

  group('search_food 参数校验', () {
    test('关键词非空且 ≤20 字', () {
      expect(AiToolArgs.searchQuery({'query': ' 牛肉面 '}), '牛肉面');
      expect(() => AiToolArgs.searchQuery({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.searchQuery({'query': '   '}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.searchQuery({'query': 'x' * 21}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.searchQuery({'query': 'x' * 20}).length, 20);
    });
  });

  group('AiToolSpecs 工具清单', () {
    test('20 个工具、名称唯一、读写两类正好覆盖全部', () {
      final names = AiToolSpecs.defs
          .map((d) => (d['function'] as Map)['name'] as String)
          .toList();
      expect(names, hasLength(24));
      expect(names.toSet(), hasLength(24));
      expect(names.toSet(),
          {...AiToolSpecs.writeTools, ...AiToolSpecs.readOnlyTools});
      expect(AiToolSpecs.writeTools.union(AiToolSpecs.readOnlyTools),
          hasLength(24));
      // 只读工具不重叠写工具
      expect(AiToolSpecs.writeTools.intersection(AiToolSpecs.readOnlyTools),
          isEmpty);
      // 原有 5 个工具名不变
      expect(
          names,
          containsAll([
            'log_weight',
            'log_water',
            'query_stats',
            'log_food',
            'log_workout',
          ]));
      // 第二批新增 8 个
      expect(
          names,
          containsAll([
            'log_measurements',
            'set_target_weight',
            'update_profile',
            'set_diet_target',
            'set_reminder',
            'delete_records',
            'manage_goal',
            'search_food',
          ]));
      // 第三批新增 3 个（动作库 + 训练模板）
      expect(
          names,
          containsAll([
            'query_exercises',
            'create_exercise',
            'create_template',
          ]));
      // 第四批新增 1 个（批量加动作）
      expect(names, containsAll(['create_exercises']));
      // 第五批新增 2 个（联网搜索 / 读网页，只读自动执行）
      expect(names, containsAll(['web_search', 'fetch_url']));
      // 第六批新增 1 个（按模板直接开练，需确认但不落库）
      expect(names, containsAll(['start_workout']));
      // 第七批新增 1 个（一键清空全部数据：毁灭性，红卡 + 二次确认）
      expect(names, containsAll(['wipe_all_data']));
      expect(AiToolSpecs.destructiveTools, contains('wipe_all_data'));
      expect(AiToolSpecs.writeTools, contains('wipe_all_data'),
          reason: '写操作从第一天起就弹确认卡，没有"降级前可直接生效"的空间');
    });

    test('每个工具都有描述与 object 参数', () {
      for (final d in AiToolSpecs.defs) {
        final fn = d['function'] as Map;
        expect((fn['description'] as String).isNotEmpty, isTrue);
        final params = fn['parameters'] as Map;
        expect(params['type'], 'object');
        expect(params['properties'], isA<Map>());
        // required 要么不写（无必填参数），要么是非空数组；
        // 空数组会被 OpenAI 兼容网关判非法 schema → 400
        if (params.containsKey('required')) {
          expect(params['required'], isA<List>());
          expect(params['required'] as List, isNotEmpty,
              reason: '${fn['name']} 的 required 不能是空数组，应直接省略该键');
        }
      }
    });

    test('AiToolPreview 默认不是危险操作', () {
      const call = AiToolCall(
          id: 'call_1',
          name: 'log_weight',
          argumentsJson: '{"weight_jin":161}');
      const preview = AiToolPreview(
        call: call,
        label: '记录体重',
        detail: '161.0 斤 · 今天',
        needsConfirm: true,
      );
      expect(preview.isDestructive, isFalse);
      const dangerous = AiToolPreview(
        call: call,
        label: '删除记录',
        detail: '删除今天的 1 条记录',
        needsConfirm: true,
        isDestructive: true,
      );
      expect(dangerous.isDestructive, isTrue);
    });
  });

  group('提示词新增工具约定', () {
    test('危险操作先说明后果 / 目标语义 / 不猜 goal_id', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('先一句话说明后果'));
      expect(prompt, contains('set_target_weight'));
      expect(prompt, contains('manage_goal(action:create)'));
      expect(prompt, contains('不要凭猜的 id'));
    });

    test('动作库 / 模板：先查动作再建模板，缺动作先加动作', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('query_exercises'));
      expect(prompt, contains('create_exercise'));
      expect(prompt, contains('建训练模板前先用 query_exercises 确认动作存在'));
      expect(prompt, contains('先 create_exercise 加进动作库'));
      expect(prompt, contains('帮我加个动作'));
    });
  });

  // ═══════════ 安全不变量：工具清单 / 预览层（假仓储，不连数据库） ═══════════

  group('工具清单一致性', () {
    test('20 个常量与 defs 一一对应（无遗漏 / 无多余）', () {
      expect(_defToolNames(), {
        AiToolSpecs.logWeight,
        AiToolSpecs.logWater,
        AiToolSpecs.logFood,
        AiToolSpecs.logWorkout,
        AiToolSpecs.logMeasurements,
        AiToolSpecs.setTargetWeight,
        AiToolSpecs.updateProfile,
        AiToolSpecs.setDietTarget,
        AiToolSpecs.setReminder,
        AiToolSpecs.manageGoal,
        AiToolSpecs.deleteRecords,
        AiToolSpecs.wipeAllData,
        AiToolSpecs.queryMeasurements,
        AiToolSpecs.updateMeasurement,
        AiToolSpecs.deleteMeasurement,
        AiToolSpecs.queryStats,
        AiToolSpecs.searchFood,
        AiToolSpecs.queryExercises,
        AiToolSpecs.webSearch,
        AiToolSpecs.fetchUrl,
        AiToolSpecs.createExercise,
        AiToolSpecs.createExercises,
        AiToolSpecs.createTemplate,
        AiToolSpecs.startWorkout,
      });
    });

    test('写 / 只读 / 危险三集合互斥，并集 = 全部工具', () {
      final all = _defToolNames();
      const write = AiToolSpecs.writeTools;
      const readOnly = AiToolSpecs.readOnlyTools;
      const destructive = AiToolSpecs.destructiveTools;

      expect(write.intersection(readOnly), isEmpty, reason: '写工具不能出现在只读集合');
      expect(destructive.intersection(readOnly), isEmpty,
          reason: '危险工具不能是自动执行的只读工具');
      expect(destructive.difference(write), isEmpty,
          reason: '危险工具必须同时是写操作（必须走确认卡）');
      expect({...write, ...readOnly, ...destructive}, all,
          reason: '三集合并集必须覆盖全部工具');
      expect(write.length + readOnly.length, all.length,
          reason: '写 + 只读应正好划分全部工具');
      expect(readOnly, hasLength(6),
          reason: '只允许 query_stats / search_food / query_exercises / '
              'query_measurements / web_search / fetch_url 自动执行');
      expect(
          AiToolSpecs.destructiveTools,
          {
            AiToolSpecs.deleteRecords,
            AiToolSpecs.deleteMeasurement,
            AiToolSpecs.wipeAllData,
          },
          reason: '危险工具有三个：删记录 / 删身体记录 / 清空全部数据');
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.queryExercises), isTrue);
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.webSearch), isTrue);
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.fetchUrl), isTrue);
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.createExercise), isFalse);
      expect(AiToolSpecs.isReadOnly(AiToolSpecs.createTemplate), isFalse);
      expect(write, contains(AiToolSpecs.createExercise));
      expect(write, contains(AiToolSpecs.createExercises));
      expect(write, contains(AiToolSpecs.createTemplate));
      expect(write, contains(AiToolSpecs.startWorkout),
          reason: '开始训练会跳界面，仍走确认卡');
      expect(AiToolSpecs.isDestructive(AiToolSpecs.startWorkout), isFalse,
          reason: '开始训练不删数据，不能挂危险样式');
    });

    test('七组 handler 白名单互不重叠，并集 = defs', () {
      final repos = _fakeReposWithData();
      final groups = <Set<String>>[
        const {AiToolSpecs.wipeAllData},
        AiToolBodyWriters(repos).toolNames,
        AiToolReaders(repos).toolNames,
        AiToolWebReaders(repos).toolNames,
        AiToolWriters(repos).toolNames,
        AiToolSettingsWriters(repos).toolNames,
        AiToolAdminWriters(repos).toolNames,
        AiToolLibraryWriters(repos).toolNames,
        AiToolWorkoutLauncher(repos).toolNames,
      ];
      final union = <String>{};
      for (final group in groups) {
        expect(union.intersection(group), isEmpty, reason: '同一工具被两个处理器认领');
        union.addAll(group);
      }
      expect(union, _defToolNames(), reason: '处理器覆盖的工具必须与 defs 完全一致');
    });
  });

  group('AiToolExecutor 预览层安全不变量', () {
    test('写工具 needsConfirm 全为 true，只读工具全为 false', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      for (final name in _defToolNames()) {
        final preview = await executor.preview(AiToolCall(
          id: 'call_$name',
          name: name,
          argumentsJson: jsonEncode(_validArgs[name]),
        ));
        expect(preview.label, isNotEmpty, reason: '$name 缺少确认卡标题');
        expect(preview.detail, isNotEmpty, reason: '$name 缺少确认卡详情');
        expect(preview.needsConfirm, AiToolSpecs.writeTools.contains(name),
            reason: '$name 的 needsConfirm 与写工具集合不一致');
        expect(
            preview.isDestructive, AiToolSpecs.destructiveTools.contains(name),
            reason: '$name 的危险标记与 destructiveTools 不一致');
      }
    });

    test('delete_records 的预览是危险样式', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      for (final type in AiRecordTypes.all) {
        final preview = await executor.preview(AiToolCall(
          id: 'call_del_$type',
          name: AiToolSpecs.deleteRecords,
          argumentsJson: jsonEncode({'type': type}),
        ));
        expect(preview.needsConfirm, isTrue);
        expect(preview.isDestructive, isTrue, reason: '删除 $type 必须是危险样式');
        expect(preview.label, contains('删除'));
      }
    });

    test('预览不写库（假仓储的写方法一旦被调用即失败）', () async {
      final repos = _fakeReposWithData();
      final executor = AiToolExecutor(repos: repos);
      for (final name in _defToolNames()) {
        await executor.preview(AiToolCall(
          id: 'call_$name',
          name: name,
          argumentsJson: jsonEncode(_validArgs[name]),
        ));
      }
    });

    test('manage_goal：complete 不算危险，delete 是危险操作', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());

      final complete = await executor.preview(const AiToolCall(
        id: 'call_goal_complete',
        name: AiToolSpecs.manageGoal,
        argumentsJson: '{"action":"complete","goal_id":7}',
      ));
      expect(complete.needsConfirm, isTrue);
      expect(complete.isDestructive, isFalse);
      expect(complete.detail, contains('#7'));

      final delete = await executor.preview(const AiToolCall(
        id: 'call_goal_delete',
        name: AiToolSpecs.manageGoal,
        argumentsJson: '{"action":"delete","goal_id":7}',
      ));
      expect(delete.needsConfirm, isTrue);
      expect(delete.isDestructive, isTrue, reason: '删除目标必须走危险样式');
      expect(delete.label, contains('删除'));
      expect(delete.detail, contains('#7'));
    });

    test('manage_goal(create) 仍是普通样式', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      final create = await executor.preview(const AiToolCall(
        id: 'call_goal_create',
        name: AiToolSpecs.manageGoal,
        argumentsJson: '{"action":"create","type":"weight","target_value":140}',
      ));
      expect(create.needsConfirm, isTrue);
      expect(create.isDestructive, isFalse);
      expect(create.detail, '新建体重目标：140 斤');
    });

    test('危险标记的纯逻辑来源：只有 delete 动作', () {
      expect(AiGoalActions.destructive, {AiGoalActions.delete});
      expect(
          const AiGoalCommand(action: AiGoalActions.delete, goalId: 3)
              .isDestructive,
          isTrue);
      expect(
          const AiGoalCommand(action: AiGoalActions.complete, goalId: 3)
              .isDestructive,
          isFalse);
      // manage_goal 的危险语义仍只来自 delete 动作；工具级危险另有三个
      expect(
          AiToolSpecs.destructiveTools,
          {
            AiToolSpecs.deleteRecords,
            AiToolSpecs.deleteMeasurement,
            AiToolSpecs.wipeAllData,
          });
    });

    test('未注册的工具名一律拦截（模型无法绕过白名单）', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      const call = AiToolCall(
          id: 'call_x', name: 'drop_all_tables', argumentsJson: '{}');
      await _expectToolRejected(() => executor.preview(call));
      await _expectToolRejected(() => executor.execute(call));
    });
  });

  group('delete_records 空数据时不假删', () {
    test('四类记录都没有时抛异常，而不是返回 ok:true', () async {
      final executor = AiToolExecutor(repos: _fakeRepos());
      for (final type in AiRecordTypes.all) {
        await _expectToolRejected(
          () => executor.preview(AiToolCall(
            id: 'call_empty_$type',
            name: AiToolSpecs.deleteRecords,
            argumentsJson: jsonEncode({'type': type}),
          )),
          reason: '空数据删除 $type 必须拒绝',
        );
      }
    });

    test('违法记录类型在预览层就被拦下', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      // 注意：大小写与首尾空格会被归一化，故 'Weight ' 属于合法值
      for (final bad in ['sleep', '', 'all', '体重']) {
        await _expectToolRejected(
          () => executor.preview(AiToolCall(
            id: 'call_bad',
            name: AiToolSpecs.deleteRecords,
            argumentsJson: jsonEncode({'type': bad}),
          )),
          reason: '非法记录类型 "$bad" 必须被拒绝',
        );
      }
    });

    test('饮水只能删除今天', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await _expectToolRejected(
        () => executor.preview(AiToolCall(
          id: 'call_water',
          name: AiToolSpecs.deleteRecords,
          argumentsJson: jsonEncode({
            'type': AiRecordTypes.water,
            'date': AiToolFormat.ymd(yesterday),
          }),
        )),
      );
    });
  });

  group('manage_goal 预览层校验', () {
    test('create 缺类型 / 缺目标值被拒绝', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      final bad = [
        {'action': 'create', 'type': 'weight'},
        {'action': 'create', 'target_value': 140},
        {'action': 'create', 'type': 'weight', 'target_value': 0},
        {'action': 'create', 'type': 'weight', 'target_value': -5},
        {'action': 'create', 'type': 'steps', 'target_value': 140},
      ];
      for (final args in bad) {
        await _expectToolRejected(
          () => executor.preview(AiToolCall(
            id: 'call_goal',
            name: AiToolSpecs.manageGoal,
            argumentsJson: jsonEncode(args),
          )),
          reason: '非法 create 参数 $args 必须被拒绝',
        );
      }
    });

    test('complete / delete 缺 goal_id 或 id 非正被拒绝', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      final bad = [
        {'action': 'complete'},
        {'action': 'delete'},
        {'action': 'delete', 'goal_id': 0},
        {'action': 'complete', 'goal_id': -1},
        {'action': 'rename', 'goal_id': 7},
      ];
      for (final args in bad) {
        await _expectToolRejected(
          () => executor.preview(AiToolCall(
            id: 'call_goal',
            name: AiToolSpecs.manageGoal,
            argumentsJson: jsonEncode(args),
          )),
          reason: '非法参数 $args 必须被拒绝',
        );
      }
    });
  });

  group('新增参数边界值', () {
    test('围度 30~200 含端点，越界即拒绝', () {
      expect(AiToolArgs.measurements({'waist_cm': 30}).waistCm, 30);
      expect(AiToolArgs.measurements({'waist_cm': 200}).waistCm, 200);
      expect(() => AiToolArgs.measurements({'waist_cm': 29.9}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.measurements({'waist_cm': 200.1}),
          throwsA(isA<AiToolException>()));
    });

    test('身高 100~250 含端点，越界即拒绝', () {
      expect(AiToolArgs.profile({'height_cm': 100}).heightCm, 100);
      expect(AiToolArgs.profile({'height_cm': 250}).heightCm, 250);
      expect(() => AiToolArgs.profile({'height_cm': 99.5}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'height_cm': 250.5}),
          throwsA(isA<AiToolException>()));
    });

    test('出生年 1920 ~（今年-10）含端点', () {
      final maxYear = DateTime.now().year - 10;
      expect(AiToolArgs.profile({'birth_year': 1920}).birthYear, 1920);
      expect(AiToolArgs.profile({'birth_year': maxYear}).birthYear, maxYear);
      expect(() => AiToolArgs.profile({'birth_year': 1919}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.profile({'birth_year': maxYear + 1}),
          throwsA(isA<AiToolException>()));
    });

    test('宏量 0~500 / 热量 800~5000 含端点', () {
      expect(AiToolArgs.dietTarget({'protein_g': 0}).proteinG, 0);
      expect(AiToolArgs.dietTarget({'protein_g': 500}).proteinG, 500);
      expect(() => AiToolArgs.dietTarget({'protein_g': -0.1}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'protein_g': 500.1}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'calories': 799.9}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.dietTarget({'calories': 5000.1}),
          throwsA(isA<AiToolException>()));
    });

    test('小时 0~23 / 分钟 0~59 含端点，负值与越界拒绝', () {
      expect(AiToolArgs.optionalHour({'hour': 0}), 0);
      expect(AiToolArgs.optionalHour({'hour': 23}), 23);
      expect(AiToolArgs.optionalMinute({'minute': 0}), 0);
      expect(AiToolArgs.optionalMinute({'minute': 59}), 59);
      expect(() => AiToolArgs.optionalHour({'hour': -1}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.optionalMinute({'minute': -1}),
          throwsA(isA<AiToolException>()));
    });

    test('目标数值必须 > 0 且有上限', () {
      expect(AiToolArgs.goalTargetValue({'target_value': 0.1}), 0.1);
      expect(() => AiToolArgs.goalTargetValue({'target_value': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.goalTargetValue({'target_value': 200000}),
          throwsA(isA<AiToolException>()));
    });

    test('目标结束日期允许未来，超过 5 年拒绝', () {
      final sixYears = DateTime.now().add(const Duration(days: 365 * 6));
      expect(
          () =>
              AiToolArgs.goalEndDate({'end_date': AiToolFormat.ymd(sixYears)}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.goalEndDate({'end_date': '2026-06-01'}),
          DateTime(2026, 6, 1));
    });
  });

  // ═══════════ 动作库 + 训练模板（query_exercises / create_exercise / create_template） ═══════════

  group('query_exercises / create_exercise 参数校验', () {
    test('分类中文、英文都归一化成英文枚举值', () {
      const cases = {
        '徒手': 'bodyweight',
        ' bodyweight ': 'bodyweight',
        '自重': 'bodyweight',
        '器械': 'gym',
        'GYM': 'gym',
        '有氧': 'cardio',
        'cardio': 'cardio',
        '拉伸': 'stretch',
        'Stretch': 'stretch',
      };
      for (final entry in cases.entries) {
        expect(
            AiToolArgs.exerciseCategory({'category': entry.key}), entry.value,
            reason: '分类 "${entry.key}" 应归一化为 ${entry.value}');
      }
      // 归一化结果一定落在数据库枚举内
      for (final c in AiExerciseCategories.all) {
        expect(AiExerciseCategories.normalize(c), c);
      }
    });

    test('非法分类 / 缺失分类直接拒绝', () {
      for (final bad in ['', '   ', '游泳', 'yoga', 'HIIT']) {
        expect(() => AiToolArgs.exerciseCategory({'category': bad}),
            throwsA(isA<AiToolException>()),
            reason: '非法分类 "$bad" 必须拒绝');
      }
      expect(() => AiToolArgs.exerciseCategory({}),
          throwsA(isA<AiToolException>()));
      // 可选分类：缺失 / 空白返回 null，非法值仍然抛
      expect(AiToolArgs.optionalExerciseCategory({}), isNull);
      expect(AiToolArgs.optionalExerciseCategory({'category': '  '}), isNull);
      expect(() => AiToolArgs.optionalExerciseCategory({'category': '游泳'}),
          throwsA(isA<AiToolException>()));
    });

    test('动作名 1~30 字：0 与 31 拒绝', () {
      expect(AiToolArgs.exerciseName({'name': ' 深蹲 '}), '深蹲');
      expect(AiToolArgs.exerciseName({'name': 'x' * 30}).length, 30);
      expect(() => AiToolArgs.exerciseName({'name': ''}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.exerciseName({'name': '   '}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.exerciseName({'name': 'x' * 31}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.exerciseName({}), throwsA(isA<AiToolException>()));
    });

    test('目标肌群可选、超长截断到 10 字', () {
      expect(AiToolArgs.optionalMuscleGroup({}), isNull);
      expect(AiToolArgs.optionalMuscleGroup({'muscle_group': '  '}), isNull);
      expect(AiToolArgs.optionalMuscleGroup({'muscle_group': ' 腿部 '}), '腿部');
      expect(
          AiToolArgs.optionalMuscleGroup({'muscle_group': 'x' * 12}), 'x' * 10);
    });

    test('默认次数 1~100 / 默认时长 5~600 含端点', () {
      expect(AiToolArgs.optionalDefaultReps({'default_reps': 1}), 1);
      expect(AiToolArgs.optionalDefaultReps({'default_reps': 100}), 100);
      expect(AiToolArgs.optionalDefaultReps({}), isNull);
      expect(() => AiToolArgs.optionalDefaultReps({'default_reps': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.optionalDefaultReps({'default_reps': 101}),
          throwsA(isA<AiToolException>()));

      expect(AiToolArgs.optionalDefaultDurationSec({'default_duration_sec': 5}),
          5);
      expect(
          AiToolArgs.optionalDefaultDurationSec({'default_duration_sec': 600}),
          600);
      expect(AiToolArgs.optionalDefaultDurationSec({}), isNull);
      expect(
          () => AiToolArgs.optionalDefaultDurationSec(
              {'default_duration_sec': 4}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.optionalDefaultDurationSec(
              {'default_duration_sec': 601}),
          throwsA(isA<AiToolException>()));
    });

    test('动作展示文案：没有默认值就不带最后一段', () {
      expect(
          const AiExerciseInput(
            name: '保加利亚分腿蹲',
            category: 'gym',
            muscleGroup: '腿部',
            defaultReps: 12,
          ).metaLabel,
          '器械 · 腿部 · 默认 12 次');
      expect(
          const AiExerciseInput(
            name: '平板支撑',
            category: 'bodyweight',
            defaultDurationSec: 45,
          ).metaLabel,
          '徒手 · 默认 45 秒');
      expect(
          const AiExerciseInput(name: '深蹲', category: 'gym').metaLabel, '器械');
    });

    test('动作搜索关键词可选，≤20 字', () {
      expect(AiToolArgs.optionalExerciseQuery({}), isNull);
      expect(AiToolArgs.optionalExerciseQuery({'query': '  '}), isNull);
      expect(AiToolArgs.optionalExerciseQuery({'query': ' 深蹲 '}), '深蹲');
      expect(() => AiToolArgs.optionalExerciseQuery({'query': 'x' * 21}),
          throwsA(isA<AiToolException>()));
    });

    test('create_exercise 组合入参（分类 + 默认值）', () {
      final input = AiToolArgs.exercise({
        'name': ' 保加利亚分腿蹲 ',
        'category': '器械',
        'muscle_group': '腿部',
        'default_reps': 12,
      });
      expect(input.name, '保加利亚分腿蹲');
      expect(input.category, 'gym');
      expect(input.defaultReps, 12);
      expect(input.defaultDurationSec, isNull);
      expect(input.hasDefaults, isTrue);
    });
  });

  group('create_template 参数校验', () {
    test('难度归一化：中文 + 英文兼容，非法拒绝', () {
      const cases = {
        '入门': '入门',
        'beginner': '入门',
        '中阶': '中阶',
        'Intermediate': '中阶',
        '高阶': '高阶',
        'advanced': '高阶',
      };
      for (final entry in cases.entries) {
        expect(AiToolArgs.templateDifficulty({'difficulty': entry.key}),
            entry.value);
      }
      for (final bad in ['', '  ', '大师', 'expert']) {
        expect(() => AiToolArgs.templateDifficulty({'difficulty': bad}),
            throwsA(isA<AiToolException>()),
            reason: '非法难度 "$bad" 必须拒绝');
      }
      expect(() => AiToolArgs.templateDifficulty({}),
          throwsA(isA<AiToolException>()));
    });

    test('侧重归一化：中文 + 英文兼容，非法拒绝', () {
      const cases = {
        '全身': '全身',
        'full_body': '全身',
        '放松': '放松',
        'relax': '放松',
        '碎片': '碎片',
        'fragment': '碎片',
      };
      for (final entry in cases.entries) {
        expect(AiToolArgs.templateFocus({'focus': entry.key}), entry.value);
      }
      for (final bad in ['', '增肌', 'bulk']) {
        expect(() => AiToolArgs.templateFocus({'focus': bad}),
            throwsA(isA<AiToolException>()),
            reason: '非法侧重 "$bad" 必须拒绝');
      }
      expect(
          () => AiToolArgs.templateFocus({}), throwsA(isA<AiToolException>()));
    });

    test('模板时长 5~180 含端点，4 与 181 拒绝', () {
      expect(AiToolArgs.templateMinutes({'minutes': 5}), 5);
      expect(AiToolArgs.templateMinutes({'minutes': 180}), 180);
      expect(() => AiToolArgs.templateMinutes({'minutes': 4}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateMinutes({'minutes': 181}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateMinutes({}),
          throwsA(isA<AiToolException>()));
    });

    test('模板名 1~30 字，说明 ≤100 字截断', () {
      expect(AiToolArgs.templateName({'name': ' 下肢力量 '}), '下肢力量');
      expect(AiToolArgs.templateName({'name': 'x' * 30}).length, 30);
      expect(() => AiToolArgs.templateName({'name': ''}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateName({'name': 'x' * 31}),
          throwsA(isA<AiToolException>()));
      expect(AiToolArgs.optionalTemplateDescription({}), isNull);
      expect(AiToolArgs.optionalTemplateDescription({'description': '  '}),
          isNull);
      expect(AiToolArgs.optionalTemplateDescription({'description': 'x' * 120}),
          'x' * 100);
    });

    test('动作数量 1~12：0 与 13 拒绝', () {
      List<Map<String, dynamic>> build(int n) => [
            for (var i = 0; i < n; i++) {'exercise_name': '深蹲'},
          ];
      expect(AiToolArgs.templateItems({'items': build(1)}), hasLength(1));
      expect(AiToolArgs.templateItems({'items': build(12)}), hasLength(12));
      expect(() => AiToolArgs.templateItems({'items': const []}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateItems({'items': build(13)}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.templateItems({}), throwsA(isA<AiToolException>()));
    });

    test('组数 1~10 / 次数 1~100 / 时长 5~600 含端点', () {
      expect(
          AiToolArgs.templateItem({'exercise_name': '深蹲', 'sets': 1}).sets, 1);
      expect(AiToolArgs.templateItem({'exercise_name': '深蹲', 'sets': 10}).sets,
          10);
      expect(() => AiToolArgs.templateItem({'exercise_name': '深蹲', 'sets': 0}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateItem({'exercise_name': '深蹲', 'sets': 11}),
          throwsA(isA<AiToolException>()));

      expect(
          AiToolArgs.templateItem({'exercise_name': '深蹲', 'reps': 1}).reps, 1);
      expect(AiToolArgs.templateItem({'exercise_name': '深蹲', 'reps': 100}).reps,
          100);
      expect(() => AiToolArgs.templateItem({'exercise_name': '深蹲', 'reps': 0}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.templateItem({'exercise_name': '深蹲', 'reps': 101}),
          throwsA(isA<AiToolException>()));

      expect(
          AiToolArgs.templateItem({'exercise_name': '平板支撑', 'duration_sec': 5})
              .durationSec,
          5);
      expect(
          AiToolArgs.templateItem(
              {'exercise_name': '平板支撑', 'duration_sec': 501}).durationSec,
          501);
      expect(
          AiToolArgs.templateItem(
              {'exercise_name': '平板支撑', 'duration_sec': 600}).durationSec,
          600);
      expect(
          () => AiToolArgs.templateItem(
              {'exercise_name': '平板支撑', 'duration_sec': 4}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.templateItem(
              {'exercise_name': '平板支撑', 'duration_sec': 601}),
          throwsA(isA<AiToolException>()));
    });

    test('reps 与 duration_sec 都不给时默认 10 次，组数默认 3', () {
      final item = AiToolArgs.templateItem({'exercise_name': '深蹲'});
      expect(item.sets, 3);
      expect(item.reps, 10);
      expect(item.durationSec, isNull);
      expect(item.targetLabel, '3×10');

      final timed = AiToolArgs.templateItem(
          {'exercise_name': '平板支撑', 'duration_sec': 45});
      expect(timed.reps, isNull, reason: '计时类动作不补默认次数');
      expect(timed.durationSec, 45);
      expect(timed.targetLabel, '3×45s');
    });

    test('动作名缺失 / 过长、单项格式非法都拒绝', () {
      expect(
          () => AiToolArgs.templateItem({}), throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateItem({'exercise_name': '   '}),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.templateItem({'exercise_name': 'x' * 31}),
          throwsA(isA<AiToolException>()));
      expect(
          () => AiToolArgs.templateItems({
                'items': ['深蹲']
              }),
          throwsA(isA<AiToolException>()));
    });

    test('组合入参 + 确认卡文案', () {
      final command = AiToolArgs.template({
        'name': '下肢力量',
        'difficulty': '中阶',
        'focus': '全身',
        'minutes': 35,
        'items': [
          {'exercise_name': '深蹲', 'sets': 4, 'reps': 12},
          {'exercise_name': '臀桥', 'sets': 3, 'reps': 15},
          {'exercise_name': '箭步蹲', 'sets': 3, 'reps': 10},
          {'exercise_name': '平板支撑', 'sets': 3, 'duration_sec': 45},
        ],
      });
      expect(command.difficulty, '中阶');
      expect(command.focus, '全身');
      expect(command.items, hasLength(4));
      expect(command.items.last.reps, isNull);
      expect(command.items.last.durationSec, 45);
      expect(command.detail, '新建模板：下肢力量 · 中阶 · 4 个动作 · 约 35 分钟');
    });
  });

  group('动作库 / 模板工具预览层', () {
    test('query_exercises：只读、不确认、detail 带关键词', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());

      final search = await executor.preview(const AiToolCall(
        id: 'call_q1',
        name: AiToolSpecs.queryExercises,
        argumentsJson: '{"query":"深蹲"}',
      ));
      expect(search.label, '查动作库');
      expect(search.detail, '搜索"深蹲"');
      expect(search.needsConfirm, isFalse);
      expect(search.isDestructive, isFalse);

      final all = await executor.preview(const AiToolCall(
        id: 'call_q2',
        name: AiToolSpecs.queryExercises,
        argumentsJson: '{}',
      ));
      expect(all.detail, '查看动作库');
      expect(all.needsConfirm, isFalse);

      final byCategory = await executor.preview(const AiToolCall(
        id: 'call_q3',
        name: AiToolSpecs.queryExercises,
        argumentsJson: '{"category":"器械"}',
      ));
      expect(byCategory.detail, '查看动作库（器械）');
    });

    test('query_exercises 执行：名称包含匹配 + 分类过滤 + 最多 8 条', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());

      final byName = await _executeJson(
          executor,
          const AiToolCall(
            id: 'call_q4',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{"query":"支撑"}',
          ));
      expect(byName['ok'], isTrue);
      expect(byName['count'], 1);
      final hit = (byName['results'] as List).first as Map<String, dynamic>;
      expect(hit['name'], '平板支撑');
      expect(hit['category'], 'bodyweight');
      expect(hit['muscle_group'], '核心');
      expect(hit['default_duration_sec'], 45);

      final byCategory = await _executeJson(
          executor,
          const AiToolCall(
            id: 'call_q5',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{"category":"徒手"}',
          ));
      expect(byCategory['count'], 2);

      // 12 个动作只回传前 8 个
      final many = AiToolExecutor(
        repos: _fakeReposWithExercises([
          for (var i = 1; i <= 12; i++)
            ExerciseEntity(id: i, name: '动作$i', category: 'gym'),
        ]),
      );
      final capped = await _executeJson(
          many,
          const AiToolCall(
            id: 'call_q6',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{}',
          ));
      expect(capped['count'], 8);
      expect(capped['results'], hasLength(AiToolReaders.maxSearchResults));
    });

    test('query_exercises 名称匹配大小写不敏感', () async {
      final latin = AiToolExecutor(
        repos: _fakeReposWithExercises(const [
          ExerciseEntity(id: 9, name: 'Plank', category: 'bodyweight'),
          ExerciseEntity(id: 10, name: 'Pull-Up', category: 'gym'),
        ]),
      );

      // 库内是「Plank」，用小写关键词也应命中
      final lower = await _executeJson(
          latin,
          const AiToolCall(
            id: 'call_q7',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{"query":"plank"}',
          ));
      expect(lower['count'], 1);
      expect((lower['results'] as List).first['name'], 'Plank');

      // 大写关键词同样命中
      final upper = await _executeJson(
          latin,
          const AiToolCall(
            id: 'call_q8',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{"query":"PULL"}',
          ));
      expect(upper['count'], 1);
      expect((upper['results'] as List).first['name'], 'Pull-Up');

      // 关键词 + 分类同时给出时，两个条件都要满足
      final combined = await _executeJson(
          latin,
          const AiToolCall(
            id: 'call_q9',
            name: AiToolSpecs.queryExercises,
            argumentsJson: '{"query":"plank","category":"gym"}',
          ));
      expect(combined['count'], 0, reason: 'Plank 属徒手，按器械过滤应为空');
    });

    test('create_exercise 预览文案与确认要求', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());

      final withDefaults = await executor.preview(const AiToolCall(
        id: 'call_e1',
        name: AiToolSpecs.createExercise,
        argumentsJson:
            '{"name":"保加利亚分腿蹲","category":"器械","muscle_group":"腿部","default_reps":12}',
      ));
      expect(withDefaults.label, '新增动作');
      expect(withDefaults.detail, '新增动作：保加利亚分腿蹲（器械 · 腿部 · 默认 12 次）');
      expect(withDefaults.needsConfirm, isTrue);
      expect(withDefaults.isDestructive, isFalse);

      final bare = await executor.preview(const AiToolCall(
        id: 'call_e2',
        name: AiToolSpecs.createExercise,
        argumentsJson: '{"name":"臀桥","category":"徒手"}',
      ));
      expect(bare.detail, '新增动作：臀桥（徒手）');
      expect(bare.needsConfirm, isTrue);
    });

    test('create_template 预览文案与确认要求', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      final preview = await executor.preview(const AiToolCall(
        id: 'call_t1',
        name: AiToolSpecs.createTemplate,
        argumentsJson:
            '{"name":"下肢力量","difficulty":"中阶","focus":"全身","minutes":35,"items":[{"exercise_name":"深蹲","sets":4,"reps":12},{"exercise_name":"平板支撑","sets":3,"duration_sec":45}]}',
      ));
      expect(preview.label, '新建训练模板');
      expect(preview.detail, '新建模板：下肢力量 · 中阶 · 2 个动作 · 约 35 分钟');
      expect(preview.needsConfirm, isTrue);
      expect(preview.isDestructive, isFalse);
    });

    test('create_template：动作名按库内 trim 精确匹配，大小写不敏感', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      // 库内是「深蹲」，给「 深蹲 」也应命中
      final preview = await executor.preview(const AiToolCall(
        id: 'call_t2',
        name: AiToolSpecs.createTemplate,
        argumentsJson:
            '{"name":"腿日","difficulty":"入门","focus":"全身","minutes":20,"items":[{"exercise_name":" 深蹲 "}]}',
      ));
      expect(preview.detail, '新建模板：腿日 · 入门 · 1 个动作 · 约 20 分钟');

      final latin = AiToolExecutor(
        repos: _fakeReposWithExercises(const [
          ExerciseEntity(id: 9, name: 'Plank', category: 'bodyweight'),
        ]),
      );
      final latinPreview = await latin.preview(const AiToolCall(
        id: 'call_t3',
        name: AiToolSpecs.createTemplate,
        argumentsJson:
            '{"name":"核心","difficulty":"入门","focus":"碎片","minutes":10,"items":[{"exercise_name":"plank"}]}',
      ));
      expect(latinPreview.needsConfirm, isTrue);
    });

    test('动作库里没有的动作：预览层就拒绝，不打扰用户确认', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      await _expectToolRejected(
        () => executor.preview(const AiToolCall(
          id: 'call_t4',
          name: AiToolSpecs.createTemplate,
          argumentsJson:
              '{"name":"上肢","difficulty":"中阶","focus":"全身","minutes":30,"items":[{"exercise_name":"火箭推举","sets":3}]}',
        )),
        reason: '动作库里没有的动作必须拒绝',
      );
      await _expectToolRejected(
        () => executor.execute(const AiToolCall(
          id: 'call_t5',
          name: AiToolSpecs.createTemplate,
          argumentsJson:
              '{"name":"上肢","difficulty":"中阶","focus":"全身","minutes":30,"items":[{"exercise_name":"火箭推举","sets":3}]}',
        )),
        reason: '执行层同样要拦下未知动作',
      );
    });

    test('create_exercise 同名动作（trim 后一致）拒绝', () async {
      final executor = AiToolExecutor(repos: _fakeReposWithData());
      await _expectToolRejected(
        () => executor.execute(const AiToolCall(
          id: 'call_e3',
          name: AiToolSpecs.createExercise,
          argumentsJson: '{"name":"深蹲","category":"器械"}',
        )),
        reason: '同名动作不能重复入库',
      );
    });

    test('create_exercise 同名判定忽略大小写：preview 与 execute 都拒绝', () async {
      // 库内是 "Plank"，请求 "plank" 属于同一个动作
      final executor = AiToolExecutor(
        repos: _fakeReposWithExercises(const [
          ExerciseEntity(id: 9, name: 'Plank', category: 'bodyweight'),
        ]),
      );
      const call = AiToolCall(
        id: 'call_e4',
        name: AiToolSpecs.createExercise,
        argumentsJson: '{"name":" plank ","category":"徒手"}',
      );

      await _expectToolRejected(
        () => executor.preview(call),
        reason: '预览阶段就要拦下同名动作（不让用户点了确认才报错）',
      );
      await _expectToolRejected(
        () => executor.execute(call),
        reason: '执行层兜底再拦一次',
      );

      try {
        await executor.preview(call);
        fail('预览阶段应当抛 AiToolException');
      } on AiToolException catch (e) {
        expect(e.message, contains('动作库里已有"plank"'));
      }
    });
  });

  // ═══════════ 批量：create_missing_exercises / create_exercises ═══════════

  group('工具轮次上限放开到 8', () {
    test('常量 = 8，文案改成"请分两步说"', () {
      expect(AiToolLimits.maxCallsPerRound, 8);
      expect(AiToolLimits.overLimitMessage, contains('请分两步说'));
      expect(AiToolLimits.overLimitMessage, contains('操作次数过多'));
    });
  });

  group('create_template 的 category / muscle_group 归一化', () {
    Map<String, dynamic> args(List<Map<String, dynamic>> items) => {
          'name': '下肢力量',
          'difficulty': '中阶',
          'focus': '全身',
          'minutes': 35,
          'items': items,
        };

    test('中文 / 英文分类都归一化成英文枚举', () {
      final cn = AiToolArgs.template(args([
        {'exercise_name': '开合跳', 'category': '有氧'},
        {'exercise_name': '拉伸腿', 'category': '拉伸'},
        {'exercise_name': '深蹲跳', 'category': '徒手'},
        {'exercise_name': '硬拉', 'category': '器械'},
      ]));
      expect(cn.items.map((e) => e.category).toList(),
          ['cardio', 'stretch', 'bodyweight', 'gym']);

      final en = AiToolArgs.template(args([
        {'exercise_name': 'Plank', 'category': 'gym'},
      ]));
      expect(en.items.first.category, 'gym');
    });

    test('没给分类时保持 null（新建时按兜底值处理）', () {
      final command = AiToolArgs.template(args([
        {'exercise_name': '开合跳'},
      ]));
      expect(command.items.first.category, isNull);
      expect(command.items.first.toNewExercise().category,
          AiExerciseCategories.fallback);
      expect(AiExerciseCategories.fallback, 'bodyweight',
          reason: '动作库 UI 只认四个值，兜底不能写 other');
    });

    test('非法分类直接拒绝（不猜用户意图）', () {
      expect(
        () => AiToolArgs.template(args([
          {'exercise_name': '开合跳', 'category': '杂技'},
        ])),
        throwsA(isA<AiToolException>()),
      );
    });

    test('muscle_group 超长截断到 10 字', () {
      final command = AiToolArgs.template(args([
        {'exercise_name': '开合跳', 'muscle_group': '腿部肌肉群特别长的名字啊啊啊'},
      ]));
      expect(command.items.first.muscleGroup, hasLength(10));
    });

    test('create_missing_exercises 默认 false，可解析 true / "true" / 1', () {
      expect(
          AiToolArgs.template(args([
            {'exercise_name': '开合跳'},
          ])).createMissingExercises,
          isFalse);
      for (final v in <Object>[true, 'true', 1, '是']) {
        final a = args([
          {'exercise_name': '开合跳'}
        ])
          ..['create_missing_exercises'] = v;
        expect(AiToolArgs.template(a).createMissingExercises, isTrue,
            reason: '$v 应解析成 true');
      }
    });
  });

  group('create_template 一次补齐缺失动作', () {
    const args = '{"name":"下肢力量","difficulty":"中阶","focus":"全身",'
        '"minutes":35,"create_missing_exercises":true,"items":['
        '{"exercise_name":"开合跳","category":"有氧"},'
        '{"exercise_name":"提膝下压","category":"徒手","muscle_group":"腹部"},'
        '{"exercise_name":"平板支撑","sets":3,"duration_sec":45}]}';

    test('开关为 true：preview 不抛错，文案带"含新建 N 个动作"', () async {
      final executor = AiToolExecutor(repos: _mutableRepos());
      final preview = await executor.preview(const AiToolCall(
        id: 'call_b1',
        name: AiToolSpecs.createTemplate,
        argumentsJson: args,
      ));
      expect(preview.label, '新建训练模板');
      expect(preview.detail, '新建模板：下肢力量 · 中阶 · 3 个动作 · 约 35 分钟（含新建 2 个动作）');
      expect(preview.needsConfirm, isTrue, reason: '批量也不许跳过确认卡');
    });

    test('开关缺省：缺动作时预览与执行都抛错（保持原行为）', () async {
      const json = '{"name":"下肢力量","difficulty":"中阶","focus":"全身",'
          '"minutes":35,"items":[{"exercise_name":"开合跳"}]}';
      final executor = AiToolExecutor(repos: _mutableRepos());
      const call = AiToolCall(
          id: 'call_b2', name: AiToolSpecs.createTemplate, argumentsJson: json);
      await _expectToolRejected(() => executor.preview(call));
      await _expectToolRejected(() => executor.execute(call));
    });

    test('列表里的动作都在库里：文案保持原样（不出现"含新建"）', () async {
      final executor = AiToolExecutor(repos: _mutableRepos());
      final preview = await executor.preview(const AiToolCall(
        id: 'call_b3',
        name: AiToolSpecs.createTemplate,
        argumentsJson: '{"name":"核心","difficulty":"入门","focus":"碎片",'
            '"minutes":10,"create_missing_exercises":true,'
            '"items":[{"exercise_name":"深蹲"},{"exercise_name":"平板支撑"}]}',
      ));
      expect(preview.detail, '新建模板：核心 · 入门 · 2 个动作 · 约 10 分钟');
    });

    test('执行：先建缺失动作再建模板，item 映射到新建动作的 id', () async {
      final exercise = _MutableExerciseRepo(_fakeExercises);
      final template = _MutableTemplateRepo();
      final executor = AiToolExecutor(
          repos: _mutableRepos(exercise: exercise, template: template));

      final result = await _executeJson(
          executor,
          const AiToolCall(
            id: 'call_b4',
            name: AiToolSpecs.createTemplate,
            argumentsJson: args,
          ));

      expect(result['ok'], isTrue);
      expect(result['template_id'], 1);
      expect(result['created_exercises'], ['开合跳', '提膝下压']);
      // 动作库：原本 3 个 + 新建 2 个
      expect(exercise.rows, hasLength(5));
      final created = exercise.rows.skip(3).toList();
      expect(created.map((e) => e.category).toList(), ['cardio', 'bodyweight']);
      expect(created.last.muscleGroup, '腹部');

      // 模板 items 指向新建的 id（新 id 从 100 起）
      final items = template.created.single.items;
      expect(items, hasLength(3));
      expect(items.map((e) => e.exerciseId).toList(), [100, 101, 3]);
    });

    test('同名缺失动作去重：忽略大小写，只建一个', () async {
      final exercise = _MutableExerciseRepo(const []);
      final template = _MutableTemplateRepo();
      final executor = AiToolExecutor(
          repos: _mutableRepos(exercise: exercise, template: template));

      final result = await _executeJson(
          executor,
          const AiToolCall(
            id: 'call_b5',
            name: AiToolSpecs.createTemplate,
            argumentsJson: '{"name":"核心","difficulty":"入门","focus":"全身",'
                '"minutes":15,"create_missing_exercises":true,"items":['
                '{"exercise_name":"Plank","category":"徒手"},'
                '{"exercise_name":" plank ","category":"器械"},'
                '{"exercise_name":"平板支撑","category":"徒手"}]}',
          ));

      expect(result['created_exercises'], ['Plank', '平板支撑']);
      expect(exercise.rows, hasLength(2), reason: '同名动作只能建一个');
      expect(template.created.single.items.map((e) => e.exerciseId).toList(),
          [100, 100, 101]);
    });

    test('二次校验：预览之后别处已把动作加进库，执行时复用、不重复建', () async {
      final exercise = _MutableExerciseRepo(const []);
      final template = _MutableTemplateRepo();
      final executor = AiToolExecutor(
          repos: _mutableRepos(exercise: exercise, template: template));

      const call = AiToolCall(
        id: 'call_b6',
        name: AiToolSpecs.createTemplate,
        argumentsJson: '{"name":"腿日","difficulty":"入门","focus":"全身",'
            '"minutes":20,"create_missing_exercises":true,'
            '"items":[{"exercise_name":"开合跳","category":"有氧"}]}',
      );

      final preview = await executor.preview(call);
      expect(preview.detail, contains('（含新建 1 个动作）'));

      // 用户还没点确认的时候，动作库被别处写进了同名动作
      exercise.rows
          .add(const ExerciseEntity(id: 7, name: '开合跳', category: 'cardio'));

      final result = await _executeJson(executor, call);
      expect(result['ok'], isTrue);
      expect(result['created_exercises'], isEmpty, reason: '已存在就该复用');
      expect(exercise.rows.where((e) => e.name == '开合跳'), hasLength(1));
      expect(template.created.single.items.single.exerciseId, 7);
    });
  });

  group('create_exercises 批量新增动作', () {
    Map<String, dynamic> batch(List<String> names) => {
          'exercises': [
            for (final name in names) {'name': name, 'category': '徒手'},
          ],
        };

    test('边界：1 个可以，10 个可以，11 个拒绝，0 个拒绝', () {
      expect(AiToolArgs.exercises(batch(['动作1'])), hasLength(1));
      expect(
          AiToolArgs.exercises(batch([for (var i = 1; i <= 10; i++) '动作$i'])),
          hasLength(10));
      expect(
          () => AiToolArgs.exercises(
              batch([for (var i = 1; i <= 11; i++) '动作$i'])),
          throwsA(isA<AiToolException>()));
      expect(() => AiToolArgs.exercises(batch(const [])),
          throwsA(isA<AiToolException>()));
    });

    test('批内同名（忽略大小写）只保留第一个', () {
      final inputs = AiToolArgs.exercises({
        'exercises': [
          {'name': 'Plank', 'category': '徒手', 'muscle_group': '核心'},
          {'name': ' plank ', 'category': '器械'},
        ],
      });
      expect(inputs, hasLength(1));
      expect(inputs.single.category, 'bodyweight');
      expect(inputs.single.muscleGroup, '核心');
    });

    test('预览文案：新增 3 个动作：A、B、C', () async {
      final executor = AiToolExecutor(repos: _mutableRepos());
      final preview = await executor.preview(const AiToolCall(
        id: 'call_be1',
        name: AiToolSpecs.createExercises,
        argumentsJson: '{"exercises":[{"name":"开合跳","category":"有氧"},'
            '{"name":"提膝下压","category":"徒手"},'
            '{"name":"深蹲跳","category":"徒手"}]}',
      ));
      expect(preview.label, '批量新增动作');
      expect(preview.detail, '新增 3 个动作：开合跳、提膝下压、深蹲跳');
      expect(preview.needsConfirm, isTrue);
      expect(preview.isDestructive, isFalse);
    });

    test('执行：库里已有同名跳过并列进 skipped', () async {
      final exercise = _MutableExerciseRepo(_fakeExercises);
      final executor = AiToolExecutor(repos: _mutableRepos(exercise: exercise));

      final result = await _executeJson(
          executor,
          const AiToolCall(
            id: 'call_be2',
            name: AiToolSpecs.createExercises,
            argumentsJson: '{"exercises":[{"name":"深蹲","category":"器械"},'
                '{"name":"开合跳","category":"有氧","default_duration_sec":60},'
                '{"name":"提膝下压","category":"徒手"}]}',
          ));

      expect(result['ok'], isTrue);
      expect(result['created_count'], 2);
      expect(result['skipped'], ['深蹲']);
      expect(exercise.rows, hasLength(5));
      final jumping = exercise.rows.firstWhere((e) => e.name == '开合跳');
      expect(jumping.defaultDurationSec, 60, reason: '默认值要一起落库');
    });
  });

  group('提示词：批量建模板 / 批量加动作', () {
    test('引导一次调用 create_template 并开启 create_missing_exercises', () {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: null);
      expect(prompt, contains('不要逐个调用工具'));
      expect(prompt, contains('create_missing_exercises'));
      expect(prompt, contains('create_exercises'));
      expect(prompt, contains('${AiToolLimits.maxCallsPerRound} 次工具调用'));
    });
  });
}

/// 执行工具并把结果解析成 Map
Future<Map<String, dynamic>> _executeJson(
    AiToolExecutor executor, AiToolCall call) async {
  final raw = await executor.execute(call);
  return jsonDecode(raw) as Map<String, dynamic>;
}

// ═══════════════════════ 测试替身（不碰数据库） ═══════════════════════

/// 断言工具调用被拦下：同时兼容同步抛出与异步 Future 失败
Future<void> _expectToolRejected(
  Future<Object?> Function() call, {
  String? reason,
}) async {
  final suffix = reason == null ? '' : '：$reason';
  try {
    await call();
  } on AiToolException {
    return;
  }
  fail('应当抛出 AiToolException，但没有抛$suffix');
}

/// defs 里注册的工具名集合
Set<String> _defToolNames() => AiToolSpecs.defs
    .map((d) => (d['function'] as Map)['name'] as String)
    .toSet();

/// 每个工具一份合法参数，用于跑通预览层
const _validArgs = <String, Map<String, dynamic>>{
  AiToolSpecs.queryMeasurements: {},
  AiToolSpecs.updateMeasurement:
      {'id': 1, 'part': 'waist', 'value': 80},
  AiToolSpecs.deleteMeasurement: {'id': 1},
  AiToolSpecs.logWeight: {'weight_jin': 160},
  AiToolSpecs.logWater: {'cups': 6},
  AiToolSpecs.logFood: {
    'food_name': '牛肉面',
    'grams': 250,
    'meal_type': 'lunch',
    'calories_per_100g': 120,
  },
  AiToolSpecs.logWorkout: {'workout_type': '力量', 'minutes': 45},
  AiToolSpecs.logMeasurements: {'waist_cm': 80},
  AiToolSpecs.setTargetWeight: {'target_jin': 140},
  AiToolSpecs.updateProfile: {'height_cm': 175},
  AiToolSpecs.setDietTarget: {'calories': 1800},
  AiToolSpecs.setReminder: {'enabled': true, 'hour': 9, 'minute': 0},
  AiToolSpecs.manageGoal: {
    'action': 'create',
    'type': 'weight',
    'target_value': 140,
  },
  AiToolSpecs.deleteRecords: {'type': 'food'},
  AiToolSpecs.queryStats: {'range': 'week'},
  AiToolSpecs.searchFood: {'query': '牛肉面'},
  AiToolSpecs.queryExercises: {'query': '深蹲'},
  AiToolSpecs.webSearch: {'query': 'DeepSeek 网页搜索 API', 'count': 3},
  AiToolSpecs.fetchUrl: {'url': 'https://example.com/article'},
  AiToolSpecs.createExercise: {
    'name': '保加利亚分腿蹲',
    'category': '器械',
    'muscle_group': '腿部',
    'default_reps': 12,
  },
  AiToolSpecs.createExercises: {
    'exercises': [
      {'name': '开合跳', 'category': '有氧'},
      {'name': '深蹲跳', 'category': '徒手', 'muscle_group': '腿部'},
    ],
  },
  AiToolSpecs.createTemplate: {
    'name': '下肢力量',
    'difficulty': '中阶',
    'focus': '全身',
    'minutes': 35,
    'items': [
      {'exercise_name': '深蹲', 'sets': 4, 'reps': 12},
      {'exercise_name': '平板支撑', 'sets': 3, 'duration_sec': 45},
    ],
  },
  AiToolSpecs.startWorkout: {'template_name': '下肢力量'},
};

/// 假模板库：给 start_workout 预览层用（模板名必须能在库里匹配到）
const _fakeTemplates = <WorkoutTemplateEntity>[
  WorkoutTemplateEntity(
    id: 1,
    name: '下肢力量',
    difficulty: '中阶',
    focus: '全身',
    minutes: 30,
    items: [
      WorkoutTemplateItemEntity(
        id: 1,
        templateId: 1,
        exerciseId: 1,
        exerciseName: '深蹲',
        category: 'gym',
        targetSets: 4,
        targetReps: 12,
      ),
      WorkoutTemplateItemEntity(
        id: 2,
        templateId: 1,
        exerciseId: 3,
        exerciseName: '平板支撑',
        category: 'bodyweight',
        targetSets: 3,
        targetDurationSec: 45,
      ),
    ],
  ),
];

/// 假动作库的固定数据（供 query_exercises / create_template 解析动作名）
const _fakeExercises = <ExerciseEntity>[
  ExerciseEntity(id: 1, name: '深蹲', category: 'gym', muscleGroup: '腿部'),
  ExerciseEntity(id: 2, name: '俯卧撑', category: 'bodyweight', muscleGroup: '胸部'),
  ExerciseEntity(
    id: 3,
    name: '平板支撑',
    category: 'bodyweight',
    muscleGroup: '核心',
    defaultDurationSec: 45,
  ),
];

/// 全空数据：用于验证"没数据不许假删"
AiToolRepos _fakeRepos() => AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
      database: fakeDatabase(),
      body: _FakeBodyRepo(const []),
      water: _FakeWaterRepo(0),
      workout: _FakeWorkoutRepo(const []),
      diet: _FakeDietRepo(const []),
      goal: _FakeGoalRepo(const []),
      settings: const _FakeSettingsRepo(),
      exercise: _FakeExerciseRepo(const []),
      template: _FakeTemplateRepo(const []),
    );

/// 每类记录都有一条今天的数据：用于跑通所有预览
AiToolRepos _fakeReposWithData() {
  final today = DateTime.now();
  return AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
    database: fakeDatabase(),
    body: _FakeBodyRepo([
      BodyMetricEntity(id: 1, date: today, weightKg: 80, waistCm: 80),
    ]),
    water: _FakeWaterRepo(5),
    workout: _FakeWorkoutRepo([
      WorkoutEntity(id: 1, date: today, type: '力量', durationSec: 2700),
    ]),
    diet: _FakeDietRepo([
      FoodLogEntity(
        id: 1,
        date: today,
        foodId: 1,
        grams: 250,
        mealType: 'lunch',
        foodName: '牛肉面',
        caloriesPer100g: 120,
      ),
    ]),
    goal: _FakeGoalRepo([
      GoalEntity(
        id: 7,
        type: 'weight',
        targetValue: 140,
        currentValue: 150,
        startDate: today,
        createdAt: today,
      ),
    ]),
    settings: const _FakeSettingsRepo(),
    exercise: _FakeExerciseRepo(_fakeExercises),
    template: _FakeTemplateRepo(_fakeTemplates),
  );
}

/// 只关心动作库内容时用：其他仓储留空
AiToolRepos _fakeReposWithExercises(List<ExerciseEntity> exercises) =>
    AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
        database: fakeDatabase(),
      body: _FakeBodyRepo(const []),
      water: _FakeWaterRepo(0),
      workout: _FakeWorkoutRepo(const []),
      diet: _FakeDietRepo(const []),
      goal: _FakeGoalRepo(const []),
      settings: const _FakeSettingsRepo(),
      exercise: _FakeExerciseRepo(exercises),
      template: _FakeTemplateRepo(const []),
    );

/// 写操作一旦被调用就抛错 —— 预览层绝不能写库
Never _previewMustNotWrite(String op) => throw StateError('预览阶段不应写库：$op');

class _FakeBodyRepo implements BodyMetricRepository {

  @override
  Future<List<BodyMetricEntity>> getRecent({int limit = 10}) async => const [];
  _FakeBodyRepo(this.rows);

  final List<BodyMetricEntity> rows;

  @override
  Future<List<BodyMetricEntity>> getAll({DateTime? from, DateTime? to}) async =>
      rows;

  @override
  Future<BodyMetricEntity?> getLatest() async =>
      rows.isEmpty ? null : rows.last;

  @override
  Future<BodyMetricEntity> create({
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  }) async =>
      _previewMustNotWrite('body.create');

  @override
  Future<void> update({
    required int id,
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  }) async =>
      _previewMustNotWrite('body.update');

  @override
  Future<void> delete(int id) async => _previewMustNotWrite('body.delete');
}

class _FakeWaterRepo implements WaterRepository {
  _FakeWaterRepo(this.cups);

  final int cups;

  @override
  Future<int> getTodayCups() async => cups;

  @override
  Future<List<WaterLogEntry>> getHistory() async => const [];

  @override
  Future<void> incrementCup() async => _previewMustNotWrite('water.increment');

  @override
  Future<void> decrementCup() async => _previewMustNotWrite('water.decrement');

  @override
  Future<void> setTodayCups(int cups) async =>
      _previewMustNotWrite('water.setTodayCups');
}

class _FakeWorkoutRepo implements WorkoutRepository {
  _FakeWorkoutRepo(this.rows);

  final List<WorkoutEntity> rows;

  @override
  Future<List<WorkoutEntity>> getAll({DateTime? from, DateTime? to}) async =>
      rows;

  @override
  Future<WorkoutEntity?> getById(int id) async => null;

  @override
  Future<WorkoutEntity> createWorkout({
    required DateTime date,
    required String type,
    int? planId,
    String? note,
    int? durationSec,
    required List<NewSetData> sets,
  }) async =>
      _previewMustNotWrite('workout.create');

  @override
  Future<void> updateWorkout({
    required int id,
    String? note,
    required List<NewSetData> sets,
  }) async =>
      _previewMustNotWrite('workout.update');

  @override
  Future<void> delete(int id) async => _previewMustNotWrite('workout.delete');
}

class _FakeDietRepo implements DietRepository {
  _FakeDietRepo(this.logs);

  final List<FoodLogEntity> logs;

  @override
  Future<List<FoodLogEntity>> getLogsByDate(DateTime date) async => logs;

  @override
  Future<double> getDailyCalories(DateTime date) async =>
      (await getDailyNutrition(date)).calories;

  @override
  Future<DailyNutrition> getDailyNutrition(DateTime date) async {
    final withMacros = logs.where((l) => l.hasMacros).length;
    final coverage = logs.isEmpty ? 0.0 : withMacros / logs.length;
    double sumOf(double? Function(FoodLogEntity) pick) => logs
        .where((l) => l.hasMacros)
        .fold<double>(0, (sum, l) => sum + (pick(l)! * l.grams / 100));
    return DailyNutrition(
      calories: logs.fold<double>(0, (sum, l) => sum + l.totalCalories),
      proteinG: coverage == 0 ? null : sumOf((l) => l.proteinPer100g),
      fatG: coverage == 0 ? null : sumOf((l) => l.fatPer100g),
      carbsG: coverage == 0 ? null : sumOf((l) => l.carbsPer100g),
      macroCoverage: coverage,
      logCount: logs.length,
      macroLogCount: withMacros,
    );
  }

  @override
  Future<List<FoodLibraryEntity>> searchFoods(
          {String? query, String? category}) async =>
      const [];

  @override
  Future<FoodLibraryEntity?> getFoodById(int id) async => null;

  @override
  Future<FoodLibraryEntity?> findFoodByName(String name) async => null;

  @override
  Future<void> addLog({
    required DateTime date,
    required int foodId,
    required double grams,
    required String mealType,
  }) async =>
      _previewMustNotWrite('diet.addLog');

  @override
  Future<void> deleteLog(int id) async =>
      _previewMustNotWrite('diet.deleteLog');

  @override
  Future<int> addCustomFood({
    required String name,
    required double caloriesPer100g,
    double? proteinPer100g,
    double? fatPer100g,
    double? carbsPer100g,
    String category = 'other',
  }) async =>
      _previewMustNotWrite('diet.addCustomFood');
}

class _FakeGoalRepo implements GoalRepository {
  _FakeGoalRepo(this.rows);

  final List<GoalEntity> rows;

  @override
  Future<List<GoalEntity>> getAll() async => rows;

  @override
  Future<GoalEntity?> getById(int id) async {
    for (final goal in rows) {
      if (goal.id == id) return goal;
    }
    return null;
  }

  @override
  Future<GoalEntity> create({
    required String type,
    String? category,
    required double targetValue,
    required DateTime startDate,
    DateTime? endDate,
  }) async =>
      _previewMustNotWrite('goal.create');

  @override
  Future<void> updateProgress(int id, double currentValue) async =>
      _previewMustNotWrite('goal.updateProgress');

  @override
  Future<void> complete(int id) async => _previewMustNotWrite('goal.complete');

  @override
  Future<void> delete(int id) async => _previewMustNotWrite('goal.delete');
}

class _FakeSettingsRepo implements UserSettingsRepository {
  const _FakeSettingsRepo();
  @override
  Future<UserSettingsEntity?> get() async => null;

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
      _previewMustNotWrite('settings.save');

  @override
  @override
  Future<void> saveNickname(String? nickname) async {}

  @override
  Future<void> saveAvatarPath(String? avatarPath) async {}

  @override
  Future<void> incrementAiHealthOverrideCount() async =>
      _previewMustNotWrite('settings.incrementAiHealthOverrideCount');

  @override
  Future<void> resetAiHealthOverrideCount() async =>
      _previewMustNotWrite('settings.resetAiHealthOverrideCount');

  @override
  Future<void> clearLock() async =>
      _previewMustNotWrite('settings.clearLock');
}

/// 假动作库：只读方法返回固定数据，写方法一律抛错（预览阶段绝不能写库）
class _FakeExerciseRepo implements ExerciseRepository {
  _FakeExerciseRepo(this.rows);

  final List<ExerciseEntity> rows;

  @override
  Future<List<ExerciseEntity>> getAll() async => rows;

  @override
  Future<List<ExerciseEntity>> getByCategory(String category) async =>
      rows.where((e) => e.category == category).toList();

  @override
  Future<ExerciseEntity?> getById(int id) async {
    for (final e in rows) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<List<ExerciseEntity>> search(String query) async {
    final q = query.trim().toLowerCase();
    return rows.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<ExerciseEntity> create(
          String name, String category, String? muscleGroup) async =>
      _previewMustNotWrite('exercise.create');

  @override
  Future<void> update(ExerciseEntity exercise) async =>
      _previewMustNotWrite('exercise.update');

  @override
  Future<void> delete(int id) async => _previewMustNotWrite('exercise.delete');

  @override
  Future<void> saveDefaults(int id,
          {int? defaultReps,
          double? defaultWeightKg,
          int? defaultDurationSec}) async =>
      _previewMustNotWrite('exercise.saveDefaults');
}

/// 假模板仓储：只读方法返回固定数据，写方法一律抛错
class _FakeTemplateRepo implements WorkoutTemplateRepository {
  _FakeTemplateRepo(this.rows);

  final List<WorkoutTemplateEntity> rows;

  @override
  Future<List<WorkoutTemplateEntity>> getAll() async => rows;

  @override
  Future<WorkoutTemplateEntity?> getById(int id) async {
    for (final t in rows) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async =>
      _previewMustNotWrite('template.create');

  @override
  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async =>
      _previewMustNotWrite('template.update');

  @override
  Future<void> delete(int id) async => _previewMustNotWrite('template.delete');
}

// ═══════════ 可变测试替身（批量新增动作要真的写进内存才能验证） ═══════════

/// 只用可变动作库 / 可变模板仓储时构造的仓储集合
AiToolRepos _mutableRepos({
  _MutableExerciseRepo? exercise,
  _MutableTemplateRepo? template,
}) =>
    AiToolRepos(
        reminderScheduler: fakeReminderScheduler(),
        database: fakeDatabase(),
      body: _FakeBodyRepo(const []),
      water: _FakeWaterRepo(0),
      workout: _FakeWorkoutRepo(const []),
      diet: _FakeDietRepo(const []),
      goal: _FakeGoalRepo(const []),
      settings: const _FakeSettingsRepo(),
      exercise: exercise ?? _MutableExerciseRepo(_fakeExercises),
      template: template ?? _MutableTemplateRepo(),
    );

/// 可变动作库：create / saveDefaults 真的写进内存（新 id 从 100 起，便于断言）
class _MutableExerciseRepo implements ExerciseRepository {
  _MutableExerciseRepo([List<ExerciseEntity> seed = const []]) {
    rows.addAll(seed);
  }

  final List<ExerciseEntity> rows = <ExerciseEntity>[];
  int _nextId = 100;

  @override
  Future<List<ExerciseEntity>> getAll() async => List<ExerciseEntity>.of(rows);

  @override
  Future<List<ExerciseEntity>> getByCategory(String category) async =>
      rows.where((e) => e.category == category).toList();

  @override
  Future<ExerciseEntity?> getById(int id) async {
    for (final e in rows) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<List<ExerciseEntity>> search(String query) async {
    final q = query.trim().toLowerCase();
    return rows.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<ExerciseEntity> create(
      String name, String category, String? muscleGroup) async {
    final entity = ExerciseEntity(
      id: _nextId++,
      name: name,
      category: category,
      muscleGroup: muscleGroup,
      isCustom: true,
    );
    rows.add(entity);
    return entity;
  }

  @override
  Future<void> update(ExerciseEntity exercise) async {
    final i = rows.indexWhere((e) => e.id == exercise.id);
    if (i >= 0) rows[i] = exercise;
  }

  @override
  Future<void> delete(int id) async {
    rows.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> saveDefaults(int id,
      {int? defaultReps,
      double? defaultWeightKg,
      int? defaultDurationSec}) async {
    final i = rows.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final old = rows[i];
    rows[i] = ExerciseEntity(
      id: old.id,
      name: old.name,
      category: old.category,
      muscleGroup: old.muscleGroup,
      isCustom: old.isCustom,
      defaultReps: defaultReps ?? old.defaultReps,
      defaultWeightKg: defaultWeightKg ?? old.defaultWeightKg,
      defaultDurationSec: defaultDurationSec ?? old.defaultDurationSec,
    );
  }
}

/// 可变模板仓储：只记录写入结果，不碰数据库
class _MutableTemplateRepo implements WorkoutTemplateRepository {
  final List<_CreatedTemplate> created = <_CreatedTemplate>[];

  @override
  Future<List<WorkoutTemplateEntity>> getAll() async => const [];

  @override
  Future<WorkoutTemplateEntity?> getById(int id) async => null;

  @override
  Future<int> create({
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {
    created.add(_CreatedTemplate(name: name, items: items));
    return created.length;
  }

  @override
  Future<void> update({
    required int id,
    required String name,
    required String difficulty,
    required String focus,
    required int minutes,
    String? description,
    required List<TemplateItemInput> items,
  }) async {}

  @override
  Future<void> delete(int id) async {}
}

/// 一次 create 调用的落库结果
class _CreatedTemplate {
  const _CreatedTemplate({required this.name, required this.items});

  final String name;
  final List<TemplateItemInput> items;
}
