import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/features/ai/domain/ai_tool_specs.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// v20：「联网搜索」开关
///
/// 只验证纯逻辑（工具清单裁剪 / 提示词口径 / 默认值 / schema 版本），
/// 不打开数据库、不发网络请求。
void main() {
  /// 取一组 schema 里的工具名
  List<String> namesOf(List<Map<String, dynamic>> defs) => defs
      .map((d) => (d['function'] as Map)['name'] as String)
      .toList(growable: false);

  String buildWith({required bool webEnabled}) {
    return AiPromptBuilder.build(
      trends: const TrendsData(),
      settings: UserSettingsEntity(id: 1, aiWebSearchEnabled: webEnabled),
    );
  }

  group('AiToolSpecs.defsFor：按开关裁剪工具清单', () {
    test('开启（默认）时与 defs 完全一致：21 个', () {
      final defs = AiToolSpecs.defsFor(webEnabled: true);
      expect(defs, hasLength(21));
      expect(namesOf(defs), namesOf(AiToolSpecs.defs));
    });

    test('关闭时 19 个，且不含 web_search / fetch_url', () {
      final defs = AiToolSpecs.defsFor(webEnabled: false);
      final names = namesOf(defs);
      expect(names, hasLength(19));
      expect(names, isNot(contains(AiToolSpecs.webSearch)));
      expect(names, isNot(contains(AiToolSpecs.fetchUrl)));
      // 其余只读工具与全部写工具都还在（关联网不影响记体重 / 查统计）
      expect(names, contains(AiToolSpecs.queryStats));
      expect(names, contains(AiToolSpecs.searchFood));
      expect(names, contains(AiToolSpecs.queryExercises));
      expect(AiToolSpecs.writeTools.difference(names.toSet()), isEmpty,
          reason: '写工具一个都不能少');
      expect(names.toSet(), {
        ...AiToolSpecs.writeTools,
        ...AiToolSpecs.readOnlyTools.difference(AiToolSpecs.webTools)
      });
    });

    test('defs 本身仍是 21 个全集（执行器与老测试依赖它不变）', () {
      expect(AiToolSpecs.defs, hasLength(21));
      expect(
          AiToolSpecs.webTools, {AiToolSpecs.webSearch, AiToolSpecs.fetchUrl});
      // 裁剪不修改原表，关闭两次结果一致（无副作用）
      final first = namesOf(AiToolSpecs.defsFor(webEnabled: false));
      final second = namesOf(AiToolSpecs.defsFor(webEnabled: false));
      expect(first, second);
    });
  });

  group('提示词口径随开关变化', () {
    test('开启时含联网四条规则（"先 web_search" / fetch_url / 来源标注）', () {
      final prompt = buildWith(webEnabled: true);
      expect(prompt, contains('需要最新、有时效性的信息'));
      expect(prompt, contains('先用 web_search 搜'));
      expect(prompt, contains('fetch_url 读正文'));
      expect(prompt, contains('引用搜索结果必须标来源'));
      expect(prompt, isNot(contains('联网已关闭')));
    });

    test('关闭时不提 web_search / fetch_url，改为一句"联网已关闭"', () {
      final prompt = buildWith(webEnabled: false);
      expect(prompt, isNot(contains('先 web_search')));
      expect(prompt, isNot(contains('fetch_url')));
      expect(prompt, contains('联网已关闭'));
      expect(prompt, contains('教练设定 → 联网搜索'));
    });

    test('开关关闭不影响其他段（角色 / 必须遵守 / 工具记录规则仍在）', () {
      final prompt = buildWith(webEnabled: false);
      expect(prompt, contains('# 角色'));
      expect(prompt, contains('# 必须遵守'));
      expect(prompt, contains('query_stats'));
      expect(prompt, contains('create_template'));
    });
  });

  group('设置项默认值', () {
    test('构造时未指定 → 默认开启', () {
      expect(const UserSettingsEntity(id: 1).aiWebSearchEnabled, isTrue);
    });

    test('显式关闭能落住', () {
      const settings = UserSettingsEntity(id: 1, aiWebSearchEnabled: false);
      expect(settings.aiWebSearchEnabled, isFalse);
    });

    test('settings 为空（首启 / 老库）时按开启处理', () {
      final prompt = AiPromptBuilder.build(trends: const TrendsData());
      expect(prompt, contains('先用 web_search 搜'));
      expect(prompt, isNot(contains('联网已关闭')));
    });
  });
}
