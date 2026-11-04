import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/ai_tool_router.dart';

import 'fake_database.dart';

/// **契约测试**：schema 声明的参数名必须能被 handler 认出来
///
/// 为什么需要它：模型唯一的信息来源是 schema。上一轮 `settings:target_weight`
/// 的 schema 写 `target_weight_jin`、handler 读 `target_jin` —— 端到端测试里
/// 我直接写 handler 认的名字，所以永远是绿的，这类 bug 测不出来。
///
/// 规则：下表的 key **只允许抄 schema**（`ai_merged_specs.dart`），
/// 不允许看 handler。任何一边改名忘了同步，这里立刻红。
const Map<String, Map<String, dynamic>> kSchemaArgs = {
  // workout
  'workout:log': {'minutes': 30},
  'workout:update': {'workout_id': 1, 'minutes': 30},
  'workout:delete': {'workout_id': 1},
  'workout:start': {'template_name': 'X'},
  // body
  'body:weight': {'weight_jin': 150},
  'body:measurements': {'waist_cm': 80},
  'body:update_measurement': {'id': 1, 'part': 'waist', 'value': 79},
  'body:delete_measurement': {'id': 1},
  // diet
  'diet:food': {'food_name': '牛肉面', 'grams': 300, 'calories_per_100g': 200},
  'diet:water': {'cups': 6},
  // settings
  'settings:target_weight': {'target_weight_jin': 140},
  'settings:diet_target': {'daily_calorie_target': 1600},
  'settings:profile': {'height_cm': 175},
  'settings:reminder': {
    'reminder_enabled': true,
    'reminder_hour': 20,
    'reminder_minute': 0,
  },
  // template
  'template:create': {'name': 'T', 'difficulty': '入门', 'minutes': 20},
  'template:delete': {'id': 1},
  // exercise
  'exercise:create': {'name': '波比跳', 'category': 'strength'},
  'exercise:create_many': {
    'exercises': [
      {'name': '开合跳', 'category': 'cardio'},
    ],
  },
  // goal
  'goal:create': {'type': 'weight', 'target_value': 65},
  'goal:complete': {'goal_id': 1},
  'goal:delete': {'goal_id': 1},
  // erase
  'erase:records': {'type': 'weight', 'date': '2025-11-02'},
  'erase:all': {'confirm': true},
};

/// 「缺参数」类错误才算契约破裂；业务校验失败（没有体重记录等）可接受
bool _isMissingArgError(Object e) {
  final msg = e.toString();
  return msg.contains('缺少') ||
      msg.contains('不支持的') ||
      msg.contains('没有给') ||
      msg.contains('必须给');
}

void main() {
  late AppDatabase db;
  late AiToolExecutor executor;

  setUp(() {
    db = fakeDatabase();
    executor = AiToolExecutor(repos: fakeToolRepos(db));
  });

  tearDown(() async => db.close());

  test('契约表覆盖 ≥18 个 action，且与路由表的 action 集合一致', () {
    expect(kSchemaArgs.length, greaterThanOrEqualTo(18));
    for (final entry in AiMergedTools.actions.entries) {
      for (final action in entry.value) {
        expect(kSchemaArgs.containsKey('${entry.key}:$action'), isTrue,
            reason: '缺少 ${entry.key}:$action 的契约样本');
      }
    }
  });

  for (final entry in kSchemaArgs.entries) {
    final parts = entry.key.split(':');
    final tool = parts[0];
    final action = parts[1];

    test('${entry.key}：schema 参数名能被 handler 认出（不报缺参数）', () async {
      final call = AiToolCall(
        id: 'c-$tool-$action',
        name: tool,
        argumentsJson: jsonEncode({'action': action, ...entry.value}),
      );

      try {
        await executor.execute(call);
      } catch (e) {
        expect(_isMissingArgError(e), isFalse,
            reason: '${entry.key} 按 schema 传参仍报缺参数 → '
                'schema 名与 handler 名不一致：$e');
      }
    });
  }
}
