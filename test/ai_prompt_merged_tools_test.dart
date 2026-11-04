import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/trends/presentation/trends_providers.dart' show TrendsData;
import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
import 'package:fittrack/features/ai/domain/ai_tool_router.dart';

/// 提示词工具段：只讲 8 个合并工具，旧工具名一个不留
void main() {
  final prompt = AiPromptBuilder.build(trends: const TrendsData());

  test('含 8 个合并工具名', () {
    for (final t in AiMergedTools.all) {
      expect(prompt, contains('`$t`'), reason: '提示词缺工具 $t');
    }
  });

  test('不含任何旧写工具名', () {
    const legacy = [
      'log_workout',
      'update_workout',
      'delete_workout',
      'start_workout',
      'log_weight',
      'log_water',
      'log_food',
      'log_measurements',
      // update_measurement 现在是 body 的 action 名（规格要求），不算残留
      'delete_measurement',
      'set_target_weight',
      'set_diet_target',
      'update_profile',
      'set_reminder',
      'create_template',
      'delete_template',
      'create_exercise',
      'create_exercises',
      'manage_goal',
      'delete_records',
      'wipe_all_data',
    ];
    for (final name in legacy) {
      expect(prompt, isNot(contains(name)), reason: '提示词仍出现旧工具名 $name');
    }
  });

  test('只读工具名保留（它们没有合并）', () {
    for (final name in const [
      'query_stats',
      'search_food',
      'query_exercises',
      'query_measurements',
      'query_workouts',
    ]) {
      expect(prompt, contains(name), reason: '只读工具 $name 应继续出现在提示词里');
    }
  });

  test('工具段不超过 18 条规则', () {
    final start = prompt.indexOf('# 工具使用');
    final end = prompt.indexOf('# 示例');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final section = prompt.substring(start, end);
    // 只数"合并工具段"自己的规则；联网（fetch_url / web_search）是独立开关
    // 管的另一段，不计入这里的 18 行预算
    final bullets = section
        .split('\n')
        .where((l) => l.trimLeft().startsWith('- '))
        .where((l) => !l.contains('fetch_url') && !l.contains('web_search'))
        .length;
    expect(bullets, lessThanOrEqualTo(18),
        reason: '工具段压到 ≤18 行为目标，避免模型读不完');
  });
}
