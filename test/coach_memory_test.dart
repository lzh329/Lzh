import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/ai_prompt_builder.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_memory_flow.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/presentation/coach_memory_providers.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/ai/data/coach_memory_extractor.dart';
import 'package:fittrack/features/ai/data/coach_memory_repository.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/domain/coach_memory_policy.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

import 'fake_database.dart';

/// 固定返回一组候选的假抽取器（不碰网络）
class _FakeExtractor extends CoachMemoryExtractor {
  _FakeExtractor(this.result);

  final List<CoachMemoryCandidate> result;

  @override
  Future<List<CoachMemoryCandidate>> extract({
    required List<String> userTurns,
    required String currentUserText,
    required List<CoachMemory> existing,
    required String? apiKey,
  }) async =>
      result;
}

/// 直接抛异常的抽取器（M-2：失败不许影响对话）
class _ThrowingExtractor extends CoachMemoryExtractor {
  @override
  Future<List<CoachMemoryCandidate>> extract({
    required List<String> userTurns,
    required String currentUserText,
    required List<CoachMemory> existing,
    required String? apiKey,
  }) async =>
      throw StateError('抽取器炸了');
}

CoachMemoryCandidate _c({
  String action = 'remember',
  String category = 'injury',
  String topic = '右膝',
  String content = '右膝半月板有旧伤',
  String quote = '我右膝半月板有旧伤',
}) =>
    CoachMemoryCandidate(
      action: action,
      category: category,
      topic: topic,
      content: content,
      quote: quote,
    );

void main() {
  late AppDatabase db;
  late CoachMemoryRepository repo;
  late UserSettingsRepositoryImpl settings;

  setUp(() async {
    db = fakeDatabase();
    repo = CoachMemoryRepository(db);
    settings = UserSettingsRepositoryImpl(db);
    // 有 Key 才会触发抽取（没 Key 就没有对话，也就不需要记忆）
    await settings.save(aiApiKey: 'sk-test-memory');
  });

  tearDown(() async {
    await db.close();
  });

  CoachMemoryService service(CoachMemoryExtractor extractor) =>
      CoachMemoryService(repo: repo, extractor: extractor, settings: settings);

  Future<CoachMemoryWriteReport?> apply(
    List<CoachMemoryCandidate> candidates, {
    String currentUserText = '我右膝半月板有旧伤',
  }) =>
      service(_FakeExtractor(candidates)).extractAndApply(
        userTurns: const ['我右膝半月板有旧伤'],
        currentUserText: currentUserText,
      );

  // ═══════════ 纯函数闸门 ═══════════

  group('topic 归一化（M7）', () {
    test('去空白、转小写、剥首尾标点', () {
      expect(CoachMemoryPolicy.normalizeTopic(' 右膝 '), '右膝');
      expect(CoachMemoryPolicy.normalizeTopic('右 膝'), '右膝');
      expect(CoachMemoryPolicy.normalizeTopic('「右膝」'), '右膝');
      expect(CoachMemoryPolicy.normalizeTopic('Right Knee'), 'rightknee');
    });

    test('空 / 超 20 字 → null（宁可少记一条，也不存孤儿记忆）', () {
      expect(CoachMemoryPolicy.normalizeTopic('   '), isNull);
      expect(CoachMemoryPolicy.normalizeTopic('。'), isNull);
      expect(CoachMemoryPolicy.normalizeTopic('啊' * 21), isNull);
      expect(CoachMemoryPolicy.normalizeTopic('啊' * 20), isNotNull);
    });
  });

  group('明确不记（M4）', () {
    test('数字型身体数据 / 手机号 / 医疗结论被本地拦下', () {
      expect(CoachMemoryPolicy.looksLikeForbidden('我现在 150 斤'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('体重 70kg'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('电话 13800138000'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('你有膝关节炎'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('我有半月板损伤'), isFalse,
          reason: '用户说的伤病是事实，要记');
      expect(CoachMemoryPolicy.looksLikeForbidden('我不吃香菜'), isFalse);
    });

    test('M4 精度：一次性信息 vs 状态改变 / 否定，10 条逐条可证伪', () {
      // ① 必须能被记住 —— 这些是 diet / agreement / schedule 里最有价值的表达。
      //    「吃素了」「不吃辣了」是**状态改变**（长期事实），不是"今天吃了什么"；
      //    上一版把"后面 2 字内出现 了"当完成体，正是把这一类误杀了。
      const remember = <String>[
        '我现在不吃辣了',
        '我现在吃素了',
        '我戒了酒',
        '我晚上十点才下班',
        '我不吃香菜',
      ];
      for (final text in remember) {
        expect(CoachMemoryPolicy.looksLikeForbidden(text), isFalse,
            reason: '误杀长期事实：$text');
      }

      // ② 必须仍被拦 —— 真正的一次性信息（动词+完成体紧贴）
      const block = <String>[
        '我今天吃了碗面',
        '今天吃了碗面',
        '刚才练了 20 分钟',
        '现在称了体重',
        '我今天跑了 5 公里',
      ];
      for (final text in block) {
        expect(CoachMemoryPolicy.looksLikeForbidden(text), isTrue,
            reason: '一次性信息没拦住：$text');
      }
    });

    test('Dart RegExp 支持 lookbehind（_oneOff 的否定式豁免依赖它）', () {
      // 换成二次判定也能做到同样语义，但先确认当前 SDK 原生支持，
      // 免得哪天升级后 lookbehind 变成"永远不匹配"或直接抛错。
      final r = RegExp(r'(?<![不没别戒])吃');
      expect(r.hasMatch('不吃'), isFalse);
      expect(r.hasMatch('吃'), isTrue);
    });

    test('一次性信息被拦（窄规则：时间前缀 + 行为动词）', () {
      expect(CoachMemoryPolicy.looksLikeForbidden('今天吃了碗面'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('刚才练了 20 分钟'), isTrue);
      expect(CoachMemoryPolicy.looksLikeForbidden('我晚上十点才下班'), isFalse,
          reason: '长期作息是 schedule 白名单内的东西，不许误杀');
    });
  });

  // ═══════════ 写入规则 ═══════════

  test('M-1：quote 编造 → 丢弃；quote 是真的 → 落库', () async {
    final report = await apply([
      _c(topic: '右膝', quote: '我右膝半月板有旧伤'),
      _c(topic: '左肩', content: '左肩有旧伤', quote: '我从没说过这句'),
    ]);
    expect(await repo.count(), 1);
    expect(report!.added, hasLength(1));
    expect((await repo.listAll()).single.topic, '右膝');
  });

  test('M-3：白名单外的 category 被丢弃', () async {
    await apply([_c(category: 'hobby', content: '喜欢打篮球', topic: '篮球')]);
    expect(await repo.count(), 0);
  });

  test('M-4：一次性信息 / 体重数字不落库', () async {
    await apply([
      _c(category: 'diet', topic: '面', content: '今天吃了碗面', quote: '今天吃了碗面'),
      _c(
          category: 'diet',
          topic: '体重',
          content: '我现在 150 斤',
          quote: '我现在 150 斤'),
    ], currentUserText: '今天吃了碗面，我现在 150 斤'.replaceAll('，', ' '));
    expect(await repo.count(), 0);
  });

  test('M-5：同 (category, topic) 二次写入只 1 行且内容被覆盖', () async {
    await apply([_c()]);
    await apply(
      [_c(content: '膝盖已经好了', quote: '我膝盖好了')],
      currentUserText: '我膝盖好了',
    );
    final all = await repo.listAll();
    expect(all, hasLength(1));
    expect(all.single.content, '膝盖已经好了');
  });

  test('M-6：action=forget 删行；不存在时不报错、不计数', () async {
    await apply([_c()]);
    expect(await repo.count(), 1);

    final gone = await apply(
      [_c(action: 'forget', quote: '我膝盖好了')],
      currentUserText: '我膝盖好了',
    );
    expect(await repo.count(), 0);
    expect(gone!.forgotten, hasLength(1));

    // 再忘一次：行已不存在 → 无变化（不留痕）
    final again = await apply(
      [_c(action: 'forget', quote: '我膝盖好了')],
      currentUserText: '我膝盖好了',
    );
    expect(again, isNull);
  });

  test('M-7：topic 为空 → 不落库', () async {
    await apply([_c(topic: '   ')]);
    expect(await repo.count(), 0);
  });

  test('M-8：content > 60 字 → 丢弃', () async {
    await apply([_c(content: '腿' * 61)]);
    expect(await repo.count(), 0);
    await apply([_c(content: '腿' * 60)]);
    expect(await repo.count(), 1);
  });

  test('M-9：总量 20 是硬闸，第 21 条挤掉最久没用的非 injury；injury 全在', () async {
    for (var i = 0; i < 5; i++) {
      await repo
          .upsert(_mem(category: 'injury', topic: '伤病$i', content: '旧伤$i'));
    }
    for (var i = 0; i < 15; i++) {
      await repo.upsert(_mem(category: 'diet', topic: '忌口$i', content: '不吃$i'));
    }
    expect(await repo.count(), 20);

    await apply([
      _c(category: 'preference', topic: '跑步', content: '讨厌跑步', quote: '我特别讨厌跑步')
    ], currentUserText: '我特别讨厌跑步');

    expect(await repo.count(), 20, reason: '总数不许超 20');
    final rows = await repo.listAll();
    expect(rows.where((m) => m.category == 'injury'), hasLength(5),
        reason: 'injury 不参与淘汰');
    expect(rows.any((m) => m.topic == '跑步'), isTrue);
  });

  test('M-9：injury 已满 5 条时新伤病直接丢弃（不挤掉旧伤病）', () async {
    for (var i = 0; i < 5; i++) {
      await repo
          .upsert(_mem(category: 'injury', topic: '伤病$i', content: '旧伤$i'));
    }
    await apply([_c(topic: '脚踝', content: '脚踝有旧伤', quote: '我脚踝有旧伤')],
        currentUserText: '我脚踝有旧伤');
    final rows = await repo.listAll();
    expect(rows, hasLength(5));
    expect(rows.any((m) => m.topic == '脚踝'), isFalse);
  });

  test('M-9：同类满额 → 淘汰该类最久未用的那条，新信息必须写得进来', () async {
    // diet 类上限 3 条（去重：perCategoryCap 决定）
    final oldest = (await repo
        .upsert(_mem(category: 'diet', topic: '香菜', content: '不吃香菜')))!;
    final mid = (await repo
        .upsert(_mem(category: 'diet', topic: '牛奶', content: '乳糖不耐')))!;
    final newest = (await repo
        .upsert(_mem(category: 'diet', topic: '辣椒', content: '不吃辣')))!;
    // 只有 "从没被注入过" 的那条最久未用 → 该被淘汰
    await repo.touch([mid.id], DateTime(2025, 11, 18));
    await repo.touch([newest.id], DateTime(2025, 11, 19));

    await apply(
      [_c(category: 'diet', topic: '海鲜', content: '海鲜过敏', quote: '我海鲜过敏')],
      currentUserText: '我海鲜过敏',
    );

    final rows = await repo.listAll();
    expect(rows, hasLength(3), reason: '同类上限仍是 3 条');
    expect(rows.any((m) => m.topic == '海鲜'), isTrue,
        reason: '新信息必须写进来（PRD M9 是"新顶旧"，不是"丢新的"）');
    expect(rows.any((m) => m.topic == '香菜'), isFalse,
        reason: '被淘汰的应是 last_used_at 最早的那条');
    expect(rows.any((m) => m.id == oldest.id), isFalse);
    expect(rows.any((m) => m.topic == '牛奶'), isTrue);
    expect(rows.any((m) => m.topic == '辣椒'), isTrue);
  });

  test('M-15：记忆开关关 → 不写、不注入', () async {
    await settings.saveCoachEngagement(memoryEnabled: false);
    final report = await apply([_c()]);
    expect(report, isNull);
    expect(await repo.count(), 0);
    expect(await service(_FakeExtractor(const [])).promptLines(), isEmpty);
  });

  // ═══════════ 注入 ═══════════

  group('注入（M10 / M11）', () {
    test('M-10：≤4 条，且 injury 最多占 2 席（剩下给 agreement/diet）', () {
      final all = <CoachMemory>[
        for (var i = 0; i < 3; i++)
          _entity(id: i + 1, category: 'injury', topic: 'injury$i'),
        for (var i = 0; i < 10; i++)
          _entity(id: 100 + i, category: 'diet', topic: 'diet$i'),
      ];
      final picked = CoachMemoryPolicy.selectForPrompt(all, 4);
      expect(picked, hasLength(4));
      expect(picked.where((m) => m.category == 'injury'), hasLength(2),
          reason: 'injury 上限 2：不许 4 条伤病把 agreement/diet 全挤掉');
      expect(picked.where((m) => m.category == 'diet'), hasLength(2));
    });

    test('M-10：injury 只有 1 条时，剩余 3 席给其它类且按优先级', () {
      final all = <CoachMemory>[
        _entity(id: 1, category: 'preference', topic: 'p'),
        _entity(id: 2, category: 'schedule', topic: 's'),
        _entity(id: 3, category: 'diet', topic: 'd'),
        _entity(id: 4, category: 'agreement', topic: 'a'),
        _entity(id: 5, category: 'injury', topic: 'i'),
      ];
      final picked = CoachMemoryPolicy.selectForPrompt(all, 4);
      expect(picked.map((m) => m.category).toList(),
          ['injury', 'agreement', 'diet', 'schedule'],
          reason: '安全 > 承诺 > 饮食 > 作息 > 偏好');
    });

    test('M-10：promptLines 返回「类目·内容」且更新 last_used_at', () async {
      await repo
          .upsert(_mem(category: 'injury', topic: '右膝', content: '右膝半月板有旧伤'));
      final lines = await service(_FakeExtractor(const [])).promptLines();
      expect(lines, ['伤病·右膝半月板有旧伤']);
      expect((await repo.listAll()).single.lastUsedAt, isNotNull);
    });

    test('M-11：注入段在【用户数据】之后、【用户额外约束】之前，且不含 quote', () async {
      final prompt = AiPromptBuilder.build(
        trends: const TrendsData(),
        settings: const UserSettingsEntity(id: 1, aiConstraints: '["别客套"]'),
        memoryLines: const ['伤病·右膝半月板有旧伤'],
      );
      final dataAt = prompt.indexOf('# 用户数据');
      final memoryAt = prompt.indexOf('# 你记得的事');
      final constraintAt = prompt.indexOf('# 用户额外约束');
      expect(dataAt, greaterThanOrEqualTo(0));
      expect(memoryAt, greaterThan(dataAt));
      expect(constraintAt, greaterThan(memoryAt));
      expect(prompt.contains('- 伤病·右膝半月板有旧伤'), isTrue);
    });

    test('提示词预览走只读挑选：有记忆行，但不写 last_used_at', () async {
      await repo
          .upsert(_mem(category: 'injury', topic: '右膝', content: '右膝半月板有旧伤'));
      final svc = service(_FakeExtractor(const []));

      final preview = await svc.readOnlyLines();
      expect(preview, ['伤病·右膝半月板有旧伤']);
      expect((await repo.listAll()).single.lastUsedAt, isNull,
          reason: '看一眼预览不该把记忆刷成"最近用过"，那会污染 M9 的淘汰顺序');

      // 对照：真正注入 prompt 的那条路必须写 last_used_at
      final injected = await svc.promptLines();
      expect(injected, preview);
      expect((await repo.listAll()).single.lastUsedAt, isNotNull);
    });

    test('源码守卫：人设预览必须用只读记忆行（不许调 promptLines）', () {
      final src =
          File('lib/features/ai/presentation/pages/ai_persona_page.dart')
              .readAsStringSync();
      expect(src.contains('readOnlyLines'), isTrue,
          reason: '预览漏记忆段 → 用户看不到「你记得的事」怎么进 prompt');
      expect(src.contains('promptLines'), isFalse,
          reason: '预览绝不能调 promptLines：它会写 last_used_at');
    });

    test('M-11：没有记忆时整段不出现（不留空标题）', () {
      final prompt = AiPromptBuilder.build(trends: const TrendsData());
      expect(prompt.contains('# 你记得的事'), isFalse);
    });

    test('既有调用点零改动：不传 memoryLines 也能编译运行', () {
      final prompt = AiPromptBuilder.build(
        trends: const TrendsData(),
        settings: null,
      );
      expect(prompt, isNotEmpty);
    });
  });

  // ═══════════ P-1：两个 clear 互不串台 ═══════════

  test('P-1：清空聊天记录不动记忆；清空记忆不动聊天记录', () async {
    await apply([_c()]);
    await db.into(db.aiChatMessages).insert(
        AiChatMessagesCompanion.insert(role: 'user', content: '我右膝半月板有旧伤'));

    await db.delete(db.aiChatMessages).go();
    expect(await repo.count(), 1, reason: '清聊天记录不清记忆');

    await service(_FakeExtractor(const [])).clearAll();
    expect(await db.select(db.aiChatMessages).get(), isEmpty);
  });

  // ═══════════ M-12 / M-2：留痕（不经 UI，直接测流程函数） ═══════════

  group('对话内留痕（M12 / M2）', () {
    test('M-12：本轮新增 2 条 → 只补 1 条 🧠 消息，且用「·」合并', () async {
      final traces = <String>[];
      await runMemoryExtraction(
        service: service(_FakeExtractor([
          _c(topic: '右膝', quote: '我右膝半月板有旧伤'),
          _c(category: 'diet', topic: '香菜', content: '不吃香菜', quote: '我不吃香菜'),
        ])),
        userTurns: const ['我右膝半月板有旧伤，我不吃香菜'],
        currentUserText: '我右膝半月板有旧伤，我不吃香菜',
        sourceMessageId: null,
        appendTrace: (t) async => traces.add(t),
      );
      expect(traces, hasLength(1));
      expect(traces.single, startsWith('🧠 已记住：'));
      expect(traces.single, contains('右膝半月板有旧伤'));
      expect(traces.single, contains('不吃香菜'));
      expect(traces.single, contains(' · '));
      expect(traces.single, contains('教练记得的事'));
    });

    test('M-12：本轮无变化 → 不留痕', () async {
      final traces = <String>[];
      await runMemoryExtraction(
        service: service(_FakeExtractor(const [])),
        userTurns: const ['今天天气不错'],
        currentUserText: '今天天气不错',
        sourceMessageId: null,
        appendTrace: (t) async => traces.add(t),
      );
      expect(traces, isEmpty);
    });

    test('M-2：抽取器抛异常 → 流程不抛、不留痕、已有记忆不受影响', () async {
      await repo
          .upsert(_mem(category: 'injury', topic: '右膝', content: '右膝半月板有旧伤'));
      final traces = <String>[];
      await runMemoryExtraction(
        service: service(_ThrowingExtractor()),
        userTurns: const ['我右膝半月板有旧伤'],
        currentUserText: '我右膝半月板有旧伤',
        sourceMessageId: null,
        appendTrace: (t) async => traces.add(t),
      );
      expect(traces, isEmpty);
      expect(await repo.count(), 1);
    });

    test('纯 forget 的轮次说「已忘掉」而不是「已记住」', () async {
      await repo
          .upsert(_mem(category: 'injury', topic: '右膝', content: '右膝半月板有旧伤'));
      final traces = <String>[];
      await runMemoryExtraction(
        service: service(_FakeExtractor([
          _c(action: 'forget', quote: '我膝盖好了'),
        ])),
        userTurns: const ['我膝盖好了'],
        currentUserText: '我膝盖好了',
        sourceMessageId: null,
        appendTrace: (t) async => traces.add(t),
      );
      expect(traces.single, startsWith('🧠 已忘掉：'));
      expect(await repo.count(), 0);
    });

    test('recentUserTurns 只取最近 3 条 user 原话，跳过图片占位', () {
      final turns = recentUserTurns([
        const AiMessage(role: 'user', content: '第一句'),
        const AiMessage(role: 'assistant', content: '不是用户说的'),
        const AiMessage(role: 'user', content: '第二句'),
        const AiMessage(role: 'user', content: '[图片]'),
        const AiMessage(role: 'user', content: '第三句'),
        const AiMessage(role: 'user', content: '第四句'),
      ]);
      expect(turns, ['第二句', '第三句', '第四句']);
    });
  });

  // ═══════════ 接线：ai_chat_notifier 的抽取入口（M-12 端到端） ═══════════

  group('对话接线', () {
    test('一轮对话结束后自动抽取一次，并补一条 🧠 留痕', () async {
      final chatRepo = _FakeChatRepository(db);
      var rounds = 0;
      final container = ProviderContainer(overrides: [
        userSettingsProvider.overrideWith((ref) async =>
            const UserSettingsEntity(id: 1, aiApiKey: 'sk-test')),
        aiChatRepoProvider.overrideWithValue(chatRepo),
        trendsDataProvider.overrideWith((ref) async => const TrendsData()),
        coachMemoryServiceProvider.overrideWithValue(service(_FakeExtractor([
          _c(topic: '右膝', quote: '我右膝半月板有旧伤'),
        ]))),
        aiChatProvider.overrideWith((ref) => AiChatNotifier(
              ref,
              roundRunner: ({
                required apiKey,
                required messages,
                required onDelta,
                double temperature = 0.9,
                bool searchEnabled = true,
        bool fetchEnabled = true,
                AiProvider? provider,
              }) async {
                rounds++;
                return const AiChatRoundResult(content: '知道了，注意别做深蹲');
              },
            )),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(aiChatProvider.notifier);
      await _waitFor(container);
      await notifier.send('我右膝半月板有旧伤');
      // 抽取是 fire-and-forget，给它几个 microtask
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(rounds, 1);
      expect(await repo.count(), 1, reason: '记忆落库');
      expect(chatRepo.addCalls, ['user', 'assistant', 'assistant'],
          reason: '最后那条 assistant 是 🧠 留痕');
      expect(chatRepo.stored.last, contains('🧠 已记住：'));
      expect(
        container.read(aiChatProvider).messages.last.content,
        contains('🧠 已记住：'),
      );
    });

    test('抽取器抛异常时 send 正常完成、assistant 已落库、不留痕（M-2）', () async {
      final chatRepo = _FakeChatRepository(db);
      final container = ProviderContainer(overrides: [
        userSettingsProvider.overrideWith((ref) async =>
            const UserSettingsEntity(id: 1, aiApiKey: 'sk-test')),
        aiChatRepoProvider.overrideWithValue(chatRepo),
        trendsDataProvider.overrideWith((ref) async => const TrendsData()),
        coachMemoryServiceProvider
            .overrideWithValue(service(_ThrowingExtractor())),
        aiChatProvider.overrideWith((ref) => AiChatNotifier(
              ref,
              roundRunner: ({
                required apiKey,
                required messages,
                required onDelta,
                double temperature = 0.9,
                bool searchEnabled = true,
        bool fetchEnabled = true,
                AiProvider? provider,
              }) async =>
                  const AiChatRoundResult(content: '好的'),
            )),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(aiChatProvider.notifier);
      await _waitFor(container);
      await notifier.send('我右膝半月板有旧伤');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(chatRepo.addCalls, ['user', 'assistant'], reason: '不许留痕');
      expect(container.read(aiChatProvider).isStreaming, isFalse);
      expect(container.read(aiChatProvider).error, isNull);
    });

    test('记忆关闭时抽取短路（不写、不留痕）（M-15）', () async {
      await settings.saveCoachEngagement(memoryEnabled: false);
      final chatRepo = _FakeChatRepository(db);
      final container = ProviderContainer(overrides: [
        userSettingsProvider.overrideWith((ref) async =>
            const UserSettingsEntity(
                id: 1, aiApiKey: 'sk-test', coachMemoryEnabled: false)),
        aiChatRepoProvider.overrideWithValue(chatRepo),
        trendsDataProvider.overrideWith((ref) async => const TrendsData()),
        coachMemoryServiceProvider.overrideWithValue(service(_FakeExtractor([
          _c(),
        ]))),
        aiChatProvider.overrideWith((ref) => AiChatNotifier(
              ref,
              roundRunner: ({
                required apiKey,
                required messages,
                required onDelta,
                double temperature = 0.9,
                bool searchEnabled = true,
        bool fetchEnabled = true,
                AiProvider? provider,
              }) async =>
                  const AiChatRoundResult(content: '好的'),
            )),
      ]);
      addTearDown(container.dispose);

      final notifier = container.read(aiChatProvider.notifier);
      await _waitFor(container);
      await notifier.send('我右膝半月板有旧伤');
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(await repo.count(), 0);
      expect(chatRepo.addCalls, ['user', 'assistant']);
    });
  });

  // ═══════════ 报告文案 ═══════════

  test('报告 summary 超过 3 条时收口成「等 N 条」', () {
    final report = CoachMemoryWriteReport(
      added: [
        CoachMemory(
          id: 1,
          category: 'diet',
          topic: 'a',
          content: 'A',
          quote: 'A',
          createdAt: _t,
          updatedAt: _t,
        ),
        CoachMemory(
          id: 2,
          category: 'diet',
          topic: 'b',
          content: 'B',
          quote: 'B',
          createdAt: _t,
          updatedAt: _t,
        ),
        CoachMemory(
          id: 3,
          category: 'diet',
          topic: 'c',
          content: 'C',
          quote: 'C',
          createdAt: _t,
          updatedAt: _t,
        ),
        CoachMemory(
          id: 4,
          category: 'diet',
          topic: 'd',
          content: 'D',
          quote: 'D',
          createdAt: _t,
          updatedAt: _t,
        ),
      ],
      updated: [],
      forgotten: [],
      evicted: 0,
    );
    expect(report.summary, 'A · B · C 等 4 条');
    expect(report.isEmpty, isFalse);
  });
}

/// 等 notifier 的异步初始化（读 Key / 读历史）落地
Future<void> _waitFor(ProviderContainer container) async {
  for (var i = 0; i < 100; i++) {
    if (container.read(aiChatProvider).hasKey) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('等待超时：notifier 初始化没有完成');
}

/// 内存版聊天仓库（不碰真实数据库）
class _FakeChatRepository extends AiChatRepository {
  _FakeChatRepository(super.db);

  final List<String> addCalls = <String>[];
  final List<String> stored = <String>[];

  @override
  Future<List<AiMessage>> getHistory() async => const [];

  @override
  Future<void> add(
    String role,
    String content, {
    List<CoachChip> chips = const [],
  }) async {
    addCalls.add(role);
    stored.add(content);
  }

  @override
  Future<void> clear() async {
    addCalls.clear();
    stored.clear();
  }
}

final DateTime _t = DateTime(2025, 11, 17);

CoachMemoriesCompanion _mem({
  required String category,
  required String topic,
  required String content,
}) =>
    CoachMemoriesCompanion.insert(
      category: category,
      topic: topic,
      content: content,
      quote: content,
    );

CoachMemory _entity({
  required int id,
  required String category,
  required String topic,
}) =>
    CoachMemory(
      id: id,
      category: category,
      topic: topic,
      content: '$topic 的内容',
      quote: '$topic 的原话',
      createdAt: _t,
      updatedAt: _t,
    );
