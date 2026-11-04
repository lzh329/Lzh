import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/domain/ai_tool_router.dart';

/// 工具面收敛：7 只读 + 8 合并写 = 15
///
/// 合并只发生在「模型看到的入口」，翻译点唯一（ai_tool_router.normalize），
/// handler / 仓储一行没改。
AiToolCall call(String name, Map<String, dynamic> args) => AiToolCall(
      id: 'c1',
      name: name,
      argumentsJson: jsonEncode(args),
    );

void main() {
  group('normalize：合并工具 → 旧工具', () {
    final cases = <List<dynamic>>[
      // [工具, action, 额外参数, 期望旧工具名]
      ['workout', 'log', {'minutes': 30}, 'log_workout'],
      ['workout', 'update', {'workout_id': 7}, 'update_workout'],
      ['workout', 'delete', {'workout_id': 7}, 'delete_workout'],
      ['workout', 'start', {'template_name': '胸腿日'}, 'start_workout'],
      ['body', 'weight', {'weight_jin': 150}, 'log_weight'],
      ['body', 'measurements', {'waist_cm': 80}, 'log_measurements'],
      ['body', 'update_measurement', {'id': 3}, 'update_measurement'],
      ['body', 'delete_measurement', {'id': 3}, 'delete_measurement'],
      ['diet', 'food', {'food_name': '牛肉面'}, 'log_food'],
      ['diet', 'water', {'cups': 6}, 'log_water'],
      ['settings', 'target_weight', {'target_weight_jin': 140}, 'set_target_weight'],
      ['settings', 'diet_target', {'daily_calorie_target': 1600}, 'set_diet_target'],
      ['settings', 'profile', {'height_cm': 175}, 'update_profile'],
      ['settings', 'reminder', {'reminder_hour': 20}, 'set_reminder'],
      ['template', 'create', {'name': 'T'}, 'create_template'],
      ['template', 'delete', {'id': 2}, 'delete_template'],
      ['exercise', 'create', {'name': '波比跳'}, 'create_exercise'],
      ['exercise', 'create_many', {'exercises': []}, 'create_exercises'],
      ['goal', 'create', {'type': 'weight'}, 'manage_goal'],
      ['goal', 'complete', {'goal_id': 1}, 'manage_goal'],
      ['goal', 'delete', {'goal_id': 1}, 'manage_goal'],
      ['erase', 'records', {'type': 'workout'}, 'delete_records'],
      ['erase', 'all', {'confirm': true}, 'wipe_all_data'],
    ];

    for (final c in cases) {
      test('${c[0]}:${c[1]} → ${c[3]}', () {
        final extra = Map<String, dynamic>.from(c[2] as Map);
        final out = normalize(call(c[0] as String, {'action': c[1], ...extra}));

        expect(out.name, c[3]);
        // action 被剥掉（manage_goal 除外：它自己的 action 语义）
        if (c[3] != 'manage_goal') {
          expect(out.arguments.containsKey('action'), isFalse);
        }
        // 其余参数不丢
        for (final key in extra.keys) {
          expect(out.arguments[key], extra[key], reason: '参数 $key 不能丢');
        }
      });
    }

    test('goal 的 action 转成 manage_goal 自己的 action', () {
      final out = normalize(call('goal', {'action': 'complete', 'goal_id': 3}));
      expect(out.name, 'manage_goal');
      expect(out.arguments['action'], 'complete');
      expect(out.arguments['goal_id'], 3);
    });

    test('旧工具名原样透传（兼容混用）', () {
      final out = normalize(call('log_weight', {'weight_jin': 150}));
      expect(out.name, 'log_weight');
      expect(out.arguments['weight_jin'], 150);
    });

    test('未知 action 抛可读错误', () {
      expect(() => normalize(call('workout', {'action': 'nope'})),
          throwsA(isA<AiToolException>()));
    });
  });

  group('危险判定：工具名 + action', () {
    test('erase 两个 action 都危险', () {
      expect(isMergedDestructive('erase', 'records'), isTrue);
      expect(isMergedDestructive('erase', 'all'), isTrue);
    });

    test('workout/delete、template/delete、goal/delete 危险', () {
      expect(isMergedDestructive('workout', 'delete'), isTrue);
      expect(isMergedDestructive('template', 'delete'), isTrue);
      expect(isMergedDestructive('goal', 'delete'), isTrue);
      // 改数值不危险（80→79 不该弹红卡）；删围度才危险
      expect(isMergedDestructive('body', 'update_measurement'), isFalse);
      expect(isMergedDestructive('body', 'delete_measurement'), isTrue);
    });

    test('普通写操作不危险', () {
      expect(isMergedDestructive('workout', 'log'), isFalse);
      expect(isMergedDestructive('diet', 'food'), isFalse);
      expect(isMergedDestructive('body', 'weight'), isFalse);
      expect(isMergedDestructive('settings', 'reminder'), isFalse);
    });
  });

  group('工具面数量与 schema', () {
    test('7 只读 + 8 写 = 15', () {
      expect(AiToolSpecs.defs, hasLength(15));
      expect(AiToolSpecs.useLegacyTools, isFalse);
    });

    test('8 个合并工具都在 defs 里，且都 required action', () {
      final names = AiToolSpecs.defs
          .map((d) => (d['function'] as Map)['name'] as String)
          .toSet();
      for (final t in AiMergedTools.all) {
        expect(names, contains(t), reason: '缺少合并工具 $t');
      }
      for (final def in AiToolSpecs.defs) {
        final fn = def['function'] as Map;
        if (!AiMergedTools.all.contains(fn['name'])) continue;
        final params = fn['parameters'] as Map;
        expect(params['required'], ['action'],
            reason: '${fn['name']} 必须 required action');
        final props = params['properties'] as Map;
        expect((props['action'] as Map)['enum'],
            AiMergedTools.actions[fn['name']],
            reason: '${fn['name']} 的 action enum 要与路由表一致');
      }
    });

    test('defsFor 摘掉联网工具后仍是 15 / 13', () {
      expect(AiToolSpecs.defsFor(), hasLength(15));
      expect(AiToolSpecs.defsFor(searchEnabled: false), hasLength(14));
      expect(
          AiToolSpecs.defsFor(searchEnabled: false, fetchEnabled: false),
          hasLength(13));
    });
  });
}
