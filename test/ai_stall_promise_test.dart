import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_stall_promise.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';

/// 空承诺拦截：模型回了「我去搜一下」却没调工具时，状态机自动补发一轮。
///
/// 背景（2026-10-30 真机）：用户让嘎教练搜东西，模型回「我去搜一下」就停住，
/// 等用户再问一句才真的调用 web_search。根因是模型把纯文本当成了最终答复。
void main() {
  group('isStallPromise 纯函数', () {
    test('命中空承诺词 + 短文本 → true', () {
      expect(isStallPromise('我去搜一下', const []), isTrue);
      expect(isStallPromise('稍等，我查一下', const []), isTrue);
      expect(isStallPromise('马上给你找找', const []), isTrue);
    });

    test('长文本 / 正常回答 → false', () {
      expect(isStallPromise('根据你最近一周的记录，体重下降了 1.2 斤', const []),
          isFalse);
      expect(isStallPromise('', const []), isFalse);
      expect(isStallPromise('这是超过二十四个字的正常回答内容不会被误判为承诺',
          const []), isFalse);
    });
  });

  group('状态机空承诺拦截', () {
    late AppDatabase db;
    late ProviderContainer container;
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
      await container.read(userSettingsRepoProvider).save(aiApiKey: 'sk-test');
      container.invalidate(userSettingsProvider);
      for (var i = 0;
          i < 200 && !container.read(aiChatProvider).hasKey;
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('空承诺 → 自动补发一轮，模型第二次带出工具调用', () async {
      rounds.addAll([
        // 第 1 轮：模型回空承诺、无工具调用
        const AiChatRoundResult(content: '我去搜一下'),
        // 第 2 轮（补发）：模型带出真正的搜索工具
        const AiChatRoundResult(toolCalls: [
          AiToolCall(
              id: 'c1',
              name: 'web_search',
              argumentsJson: '{"query":"减脂"}'),
        ]),
        // 第 3 轮：工具执行后，模型给出最终答案
        const AiChatRoundResult(content: '搜到了，结论如下……'),
      ]);

      await container.read(aiChatProvider.notifier).send('帮我搜下减脂方法');

      // 关键断言：请求了不止一轮（说明补发生效），且最终答案进了历史
      expect(invocations.length, greaterThanOrEqualTo(2));
      final state = container.read(aiChatProvider);
      expect(state.messages.last.content, contains('结论如下'));
      // 空承诺那句「我去搜一下」不该作为最终答复残留在消息历史末尾
      expect(state.messages.last.content, isNot('我去搜一下'));
    });

    test('正常回答不被拦截（不产生额外轮次）', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '今天也要记得喝水哦'),
      ]);

      await container.read(aiChatProvider.notifier).send('随便聊一句');

      expect(invocations.length, 1, reason: '正常回答不该触发补发');
      final state = container.read(aiChatProvider);
      expect(state.messages.last.content, '今天也要记得喝水哦');
    });
  });
}
