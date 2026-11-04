import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
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

  String buildWith({required bool webEnabled, String? providerId}) {
    return AiPromptBuilder.build(
      trends: const TrendsData(),
      settings: UserSettingsEntity(
        id: 1,
        aiWebSearchEnabled: webEnabled,
        aiProviderId: providerId,
      ),
    );
  }

  group('AiToolSpecs.defsFor：按开关裁剪工具清单', () {
    test('两个开关都开（默认）时与 defs 完全一致：28 个', () {
      final defs = AiToolSpecs.defsFor();
      expect(defs, hasLength(28));
      expect(namesOf(defs), namesOf(AiToolSpecs.defs));
    });

    test('只关搜索（非 DeepSeek）：摘掉 web_search，**保留 fetch_url**', () {
      final names =
          namesOf(AiToolSpecs.defsFor(searchEnabled: false, fetchEnabled: true));
      expect(names, hasLength(27));
      expect(names, isNot(contains(AiToolSpecs.webSearch)));
      expect(names, contains(AiToolSpecs.fetchUrl),
          reason: '读网页有本地抓取兜底，任何服务商都该能用（本 bug 的修复点）');
    });

    test('用户关掉「联网」总开关：两个都摘（26 个）', () {
      final names =
          namesOf(AiToolSpecs.defsFor(searchEnabled: false, fetchEnabled: false));
      expect(names, hasLength(26));
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

    test('搜索开、读网页关（异常组合也要正确裁剪）', () {
      final names =
          namesOf(AiToolSpecs.defsFor(searchEnabled: true, fetchEnabled: false));
      expect(names, contains(AiToolSpecs.webSearch));
      expect(names, isNot(contains(AiToolSpecs.fetchUrl)));
    });

    test('defs 本身仍是 28 个全集（执行器与老测试依赖它不变）', () {
      expect(AiToolSpecs.defs, hasLength(28));
      expect(
          AiToolSpecs.webTools, {AiToolSpecs.webSearch, AiToolSpecs.fetchUrl});
      // 裁剪不修改原表，关闭两次结果一致（无副作用）
      final first = namesOf(
          AiToolSpecs.defsFor(searchEnabled: false, fetchEnabled: false));
      final second = namesOf(
          AiToolSpecs.defsFor(searchEnabled: false, fetchEnabled: false));
      expect(first, second);
    });
  });

  group('提示词口径随开关变化', () {
    test('联网开 + DeepSeek：搜索与读网页两档规则都在', () {
      final prompt = buildWith(webEnabled: true);
      expect(prompt, contains('需要最新、有时效性的信息'));
      expect(prompt, contains('先用 web_search 搜'));
      expect(prompt, contains('fetch_url 读正文'));
      expect(prompt, contains('引用搜索结果必须标来源'));
      expect(prompt, isNot(contains('联网已关闭')));
    });

    test('联网开 + 非 DeepSeek：**保留链接/视频规则**，不写 web_search 规则', () {
      final prompt = buildWith(webEnabled: true, providerId: 'minimax');
      expect(prompt, contains('fetch_url 读正文'),
          reason: '读网页不依赖服务商（本地抓取兜底）');
      expect(prompt, contains('视频链接'), reason: '视频建模板规则也要在');
      expect(prompt, isNot(contains('先用 web_search 搜')),
          reason: '没有搜索接口，就别教它去搜');
      expect(prompt, isNot(contains('引用搜索结果必须标来源')));
      expect(prompt, isNot(contains('联网已关闭')));
    });

    test('用户关联网：两个都不提，改为一句"联网已关闭"', () {
      final prompt = buildWith(webEnabled: false);
      expect(prompt, isNot(contains('先 web_search')));
      expect(prompt, isNot(contains('fetch_url')));
      expect(prompt, contains('联网已关闭'));
      expect(prompt, contains('教练设定 → 联网'));
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
