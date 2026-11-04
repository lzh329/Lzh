import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 昵称注入回归：教练该用当前昵称称呼用户（之前漏注入，改昵称后对不上）。
void main() {
  test('设置了昵称 → 提示词含「用户昵称：XXX」', () {
    const settings = UserSettingsEntity(id: 1, nickname: '小明');
    final prompt =
        AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
    expect(prompt, contains('用户昵称：小明'));
  });

  test('没设置昵称 / 空白 → 不出现「用户昵称」', () {
    for (final settings in const [
      UserSettingsEntity(id: 1),
      UserSettingsEntity(id: 1, nickname: '   '),
    ]) {
      final prompt =
          AiPromptBuilder.build(trends: const TrendsData(), settings: settings);
      expect(prompt, isNot(contains('用户昵称')),
          reason: '昵称空时不该注入「用户昵称」行');
    }
  });
}
