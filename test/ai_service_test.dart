import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
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
}
