import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
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
}
