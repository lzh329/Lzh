import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_prompt_builder.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 工具失败回执 + 确认卡生命周期
///
/// 背景（2026-10-28 真机事故）：
/// 1. 用户让嘎教练"建一个平板支撑 90 秒一组的模板"，模型先调 start_workout
///    去找 → 库里没有 → 异常把整轮对话打死，用户只看到一个 5 秒 toast；
/// 2. 下一轮模型不知道上一轮失败（失败没有回执），凭空说"已经创建了"，
///    模板页却什么都没有。
/// 修复后：失败也回执（ok:false + 原因）并继续对话，模型必须面对失败。
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  /// 每次模型请求收到的完整 messages（含工具上下文），按调用顺序记录
  final invocations = <List<AiMessage>>[];
  final rounds = <AiChatRoundResult>[];

  AiChatRoundRunner scriptedRunner() {
    Future<AiChatRoundResult> runner({
      required String apiKey,
      required List<AiMessage> messages,
      required void Function(String delta) onDelta,
      double temperature = 0.7,
      bool webEnabled = true,
    }) async {
      invocations.add(messages);
      final i = invocations.length - 1;
      if (i >= rounds.length) {
        // 兜底：脚本耗尽时给一句纯文本，让对话自然结束
        return const AiChatRoundResult(content: '（脚本结束）');
      }
      return rounds[i];
    }

    return runner;
  }

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    invocations.clear();
    rounds.clear();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      aiChatProvider.overrideWith(
          (ref) => AiChatNotifier(ref, roundRunner: scriptedRunner())),
    ]);
    // 先把 API Key 写进设置，再构造 notifier（构造时会 load）
    await container.read(userSettingsRepoProvider).save(aiApiKey: 'sk-test');
    container.invalidate(userSettingsProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  AiChatNotifier notifier() => container.read(aiChatProvider.notifier);
  AiChatState state() => container.read(aiChatProvider);

  /// 构造函数里的 load() 是异步的，等 hasKey 就绪再发消息
  Future<void> untilReady() async {
    for (var i = 0; i < 200 && !state().hasKey; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(state().hasKey, isTrue, reason: '设置里的 API Key 应已加载');
  }

  bool hasToolReceipt(List<AiMessage> messages, String contains) {
    return messages.any((m) =>
        m.role == 'tool' &&
        m.content is String &&
        (m.content as String).contains(contains));
  }

  test('start_workout 找不到模板 → 失败回执进上下文，对话不死、模型能改道', () async {
    rounds.addAll([
      // 第 1 轮：模型像用户报障时那样，先调 start_workout 去找模板
      const AiChatRoundResult(toolCalls: [
        AiToolCall(
            id: 'c1',
            name: 'start_workout',
            argumentsJson: '{"template_name":"不存在的模板XYZ"}'),
      ]),
      // 第 2 轮：模型改调 create_template，但动作库里没有"空中转体三周半"
      const AiChatRoundResult(toolCalls: [
        AiToolCall(
            id: 'c2',
            name: 'create_template',
            argumentsJson:
                '{"name":"平板支撑 90 秒","difficulty":"入门","focus":"碎片","minutes":5,'
                '"items":[{"exercise_name":"空中转体三周半","sets":1,"duration_sec":90}]}'),
      ]),
      // 第 3 轮：模型看到两次失败，老实告诉用户下一步
      const AiChatRoundResult(
          content: '两次都没建成。我可以先把"空中转体三周半"加进动作库再建模板，要吗？'),
    ]);

    await untilReady();
    await notifier().send('帮我建一个平板支撑 90 秒一组的模板');

    // 模型请求了 3 轮，且每一轮的失败都带回了回执
    expect(invocations.length, 3, reason: '失败回执让对话继续，而不是一轮就死');
    expect(
      hasToolReceipt(invocations[1], '没找到模板'),
      isTrue,
      reason: '第 2 轮模型必须看到 start_workout 的失败原因',
    );
    expect(
      hasToolReceipt(invocations[2], '动作库里没有'),
      isTrue,
      reason: '第 3 轮模型必须看到 create_template 的失败原因',
    );
    // 全程没有 error 死亡，最后模型的话进了历史
    expect(state().error, isNull);
    expect(state().isStreaming, isFalse);
    expect(state().messages.last.role, 'assistant');
    expect(state().messages.last.content, contains('要吗'));
  });

  test('确认卡上的操作执行失败（确认后库里被插入同名动作）→ 回执 + 继续对话', () async {
    rounds.addAll([
      const AiChatRoundResult(toolCalls: [
        AiToolCall(
            id: 'c1',
            name: 'create_exercise',
            argumentsJson: '{"name":"竞争动作","category":"bodyweight"}'),
      ]),
      const AiChatRoundResult(content: '抱歉，确认的间隙库里已经被建了同名动作，没有重复创建。'),
    ]);

    await untilReady();
    await notifier().send('帮我加个动作：竞争动作');
    expect(state().pendingTool, isNotNull, reason: 'create_exercise 需要确认卡');

    // 确认前，动作被别处（如用户手动）先建了
    await container
        .read(exerciseRepoProvider)
        .create('竞争动作', 'bodyweight', null);

    await notifier().confirmTool();

    expect(
      hasToolReceipt(invocations[invocations.length - 1], '动作库里已有'),
      isTrue,
      reason: '执行失败的回执必须让模型看到，否则下一轮会幻觉"已经建好"',
    );
    expect(state().error, isNull, reason: '失败不是对话终点，模型会接着解释');
    expect(state().messages.last.role, 'assistant');
    expect(state().isStreaming, isFalse);
  });

  test('一轮带多个只读调用 → 依次执行，全部回执', () async {
    rounds.addAll([
      const AiChatRoundResult(toolCalls: [
        AiToolCall(id: 'c1', name: 'query_stats', argumentsJson: '{"range":"week"}'),
        AiToolCall(id: 'c2', name: 'search_food', argumentsJson: '{"query":"鸡胸肉"}'),
      ]),
      const AiChatRoundResult(content: '本周统计和食物搜索结果如下……'),
    ]);

    await untilReady();
    await notifier().send('看看这周情况，顺便找找鸡胸肉');

    final last = invocations.last;
    final toolMessages = last.where((m) => m.role == 'tool').toList();
    expect(toolMessages.length, 2, reason: '一轮里的多个调用都该执行并回执');
    // query_stats 的回执历史上不带 ok 字段，只验内容存在
    expect(
        toolMessages.map((m) => m.content as String).join('\n'),
        allOf(contains('"templates"'), contains('鸡胸肉')));
    expect(state().error, isNull);
    expect(state().messages.last.role, 'assistant');
  });

  test('提示词教会模型：没回执 = 没做成；建模板别拿 start_workout 去找', () {
    final prompt = AiPromptBuilder.build(trends: const TrendsData());
    expect(prompt, contains('没看到 ok:true'));
    expect(prompt, contains('不许说"已经建好 / 已经记录"'));
    expect(prompt, contains('不要先用 start_workout 去找'));
  });
}
