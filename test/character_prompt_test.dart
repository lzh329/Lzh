import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_prompt_constants.dart';
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_prompt_line.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// C-13 教练内核一字未改 + C-14 prompt 里出现当前角色名
void main() {
  // 空数据也能构建（builder 对空数据有专门的引导话术）
  const emptyTrends = TrendsData();

  group('C-13 教练人设不随角色变', () {
    test('四风格仍然存在，且每档 personaLines 非空', () {
      expect(AiCoachOptions.styles, hasLength(4),
          reason: 'doubao / guga / gentle / strict 一个都不能少');
      for (final style in AiCoachOptions.styles) {
        expect(style.personaLines, isNotEmpty, reason: style.label);
      }
      // 风格 id 顺序也要稳定（设置页按此渲染）
      expect(AiCoachOptions.styles.map((s) => s.key).toList(),
          ['doubao', 'guga', 'gentle', 'strict']);
    });

    test('豆包风格的 persona 首句逐字保持不变（人设基线）', () {
      final doubao = AiCoachOptions.styles.first;
      expect(doubao.personaLines.first, startsWith('你是「减肥嘎」App 里的搭子'));
    });

    test('通知标题仍是「嘎教练说」', () {
      // 直读源码：这行是通知渠道里用户看得见的字，改一个字就是人设变化
      final source = _read('lib/features/ai/data/coach_proactive_scheduler.dart');
      expect(source, contains("title: '嘎教练说'"));
    });

    test('prompt 结构与基线一致（四段标题都在，示例段没丢内容）', () {
      final prompt = AiPromptBuilder.build(trends: emptyTrends);
      for (final section in [
        '# 角色',
        '# 你能做什么（事实，别否认）',
        '# 必须遵守',
        '# 输出格式（有弹性，别套模板）',
        '# 工具使用',
        '# 示例（只学语气和分寸，里面的数字只是示意，真实数据一律以【用户数据】为准）',
        '# 用户数据（自动注入，真实记录）',
      ]) {
        expect(prompt, contains(section));
      }
    });

    test('搬出去的示例常量逐字未改（15 条内容 / 原 17 行代码）', () {
      // 原文是 17 行代码（含注释行与收尾的 `];`），内容项 15 条 ——
      // 搬家时只搬内容，注释留在 builder 的引用处。
      expect(kPromptExamples, hasLength(15));
      expect(kPromptExamples.first,
          '【示例 1｜闲聊 / 情绪：先接住，再给一件小到不可能拒绝的事，最后追问】');
      expect(kPromptExamples[4], '你一般几点到家？我看看能不能帮你挤出 10 分钟。');
      expect(kPromptExamples.last, '今天蛋白有点少，晚饭加个鸡蛋就够啦。');
      // 空行仍然是空行（示例之间的分隔，少了会粘成一坨）
      expect(kPromptExamples[5], '');
      expect(kPromptExamples[10], '');
    });

    test('builder 净行数 ≤321（补"按模板补记用 template_name"规则后上调）', () {
      final total = _read('lib/features/ai/data/ai_prompt_builder.dart')
          .split('\n')
          .length;
      // wc -l 统计换行数：实际行数 = 上面算出来的值 - 1（文件末尾有换行）
      // 304 → 316：联网规则拆「读网页 / 搜索」两档（+12 行）
      // 316 → 318：补「ok:false 读不到正文 → 如实说、别按标题编动作」（+2 行）
      // 318 → 319：补「模板补记从 items 原样落组次」（+1 行）
      // 319 → 320：补「补记必须带计量」（+1 行，压成单行写）
      // 320 → 321：补「按模板补记用 template_name」（+1 行）
      expect(total - 1, lessThanOrEqualTo(321),
          reason: '基线 320 + 模板补记规则净增 1 行（硬上限 321）');
    });
  });

  group('C-14 prompt 注入一行「陪伴角色」', () {
    test('咕嘎（默认）→ 含「陪伴角色」与「咕嘎」', () {
      final prompt = AiPromptBuilder.build(
        trends: emptyTrends,
        settings: const UserSettingsEntity(id: 1),
      );
      expect(prompt, contains('【陪伴角色】咕嘎'));
      expect(prompt, contains('提到它时用这个名字，不要叫咕嘎'));
    });

    test('糯糯 → 含「糯糯」，且不含「你是糯糯」（教练不许自称角色名）', () {
      final prompt = AiPromptBuilder.build(
        trends: emptyTrends,
        settings: const UserSettingsEntity(id: 1, characterId: 'nuonuo'),
      );
      expect(prompt, contains('陪伴角色'));
      expect(prompt, contains('糯糯'));
      expect(prompt.contains('你是糯糯'), isFalse,
          reason: '角色是用户选的形象，教练是产品人格，两者解耦（决策 7）');
      expect(prompt, contains('不要自称这个名字'));
    });

    test('菲比 → 含「菲比」', () {
      final prompt = AiPromptBuilder.build(
        trends: emptyTrends,
        settings: const UserSettingsEntity(id: 1, characterId: 'phoebe'),
      );
      expect(prompt, contains('【陪伴角色】菲比'));
    });

    test('非法 characterId → 按咕嘎注入（C1 在 prompt 层同样成立）', () {
      final prompt = AiPromptBuilder.build(
        trends: emptyTrends,
        settings: const UserSettingsEntity(id: 1, characterId: 'nuonuo_v2'),
      );
      expect(prompt, contains('【陪伴角色】咕嘎'));
    });

    test('只加一行：角色名出现的次数不随角色变多', () {
      int countOf(String text, String needle) =>
          needle.allMatches(text).length;
      final guga = AiPromptBuilder.build(
          trends: emptyTrends, settings: const UserSettingsEntity(id: 1));
      final nuonuo = AiPromptBuilder.build(
          trends: emptyTrends,
          settings: const UserSettingsEntity(id: 1, characterId: 'nuonuo'));
      // 「陪伴角色」四个字只出现一次（不是每段都塞）
      expect(countOf(guga, '陪伴角色'), 1);
      expect(countOf(nuonuo, '陪伴角色'), 1);
    });

    test('CharacterPromptLine 的输出格式固定（一行、无换行）', () {
      final line = CharacterPromptLine.of(CharacterCatalog.resolve('nuonuo', 0));
      expect(line.contains('\n'), isFalse);
      expect(line, startsWith('【陪伴角色】糯糯'));
    });
  });
}

/// 直接读源码（本文件是纯单测，不需要 Flutter binding）
String _read(String path) => File(path).readAsStringSync();
