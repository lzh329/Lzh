import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_stall_promise.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';

/// 写意图拦截：用户要写数据、本轮却没有工具调用 → 一定没做。
///
/// 这一版**不看模型措辞**：上一版固定词表被"已经给你加到记录里啦"绕过，
/// 真机上用户看到"记好了"却没有确认卡、没有记录。
void main() {
  group('looksLikeWriteRequest 纯函数', () {
    test('5 个正例：写操作意图', () {
      expect(looksLikeWriteRequest('帮我补记 11 月 2 日的训练'), isTrue);
      expect(looksLikeWriteRequest('记一下今天的体重'), isTrue);
      expect(looksLikeWriteRequest('删掉那个模板'), isTrue);
      expect(looksLikeWriteRequest('把目标改成 65 公斤'), isTrue);
      expect(looksLikeWriteRequest('添加一个动作叫波比跳'), isTrue);
    });

    test('3 个反例：只读 / 推荐 / 提问', () {
      expect(looksLikeWriteRequest('我这周练了几个动作'), isFalse);
      expect(looksLikeWriteRequest('推荐个训练'), isFalse);
      expect(looksLikeWriteRequest('为什么体重没降？'), isFalse);
    });
  });

  group('needWriteIntentNudge 纯函数', () {
    test('有工具调用 → 不需要补发', () {
      expect(
        needWriteIntentNudge(
          userText: '记录一下',
          content: '好的',
          hasToolCalls: true,
          alreadyNudged: false,
        ),
        isFalse,
      );
    });

    test('诚实失败 → 不补发', () {
      expect(
        needWriteIntentNudge(
          userText: '删掉 X',
          content: '找不到这个模板，需要先确认名字',
          hasToolCalls: false,
          alreadyNudged: false,
        ),
        isFalse,
      );
    });

    test('已补发过 → 不再补发（防死循环）', () {
      expect(
        needWriteIntentNudge(
          userText: '记录一下',
          content: '好的',
          hasToolCalls: false,
          alreadyNudged: true,
        ),
        isFalse,
      );
    });
  });

  group('状态机写意图拦截', () {
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
        bool searchEnabled = true,
        bool fetchEnabled = true,
        AiProvider? provider,
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
      for (var i = 0; i < 200 && !container.read(aiChatProvider).hasKey; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('关键漏判：旧词表不含的措辞也要拦住', () async {
      rounds.addAll([
        // 第 1 轮：模型换了个说法，旧词表（已记录/已补记/记好了）全都不命中
        const AiChatRoundResult(content: '好嘞，已经给你加到记录里啦 🐧'),
        // 第 2 轮（补发）：真的调用 log_workout
        const AiChatRoundResult(toolCalls: [
          AiToolCall(
            id: 'c1',
            name: 'log_workout',
            argumentsJson: '{"date":"2025-11-02","plan_name":"补记训练"}',
          ),
        ]),
      ]);

      await container.read(aiChatProvider.notifier).send('帮我补记 11 月 2 日的训练');

      expect(invocations.length, greaterThanOrEqualTo(2),
          reason: '用户要写数据却无工具调用 → 必须补发');
      final all = container
          .read(aiChatProvider)
          .messages
          .map((m) => m.content)
          .join('\n');
      expect(all, isNot(contains('已经给你加到记录里啦')), reason: '假完成那句不能进消息历史');
      // 第 2 轮已经带出工具调用 → 不再补发第 3 轮
      // （pendingTool 由确认卡流程设置；假环境里参数校验可能直接失败，
      //  所以这里断言"轮次不再增长"这个可观测行为）
      // 3 轮是正常链路：① 假完成 → ② 补发后模型调工具 → ③ 工具结果回来再答
      expect(invocations.length, lessThanOrEqualTo(3),
          reason: '模型调了工具就不该继续补发（多出的第 3 轮是工具结果回传）');
    });

    test('诚实失败不补发', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '找不到这个模板，需要先确认名字'),
      ]);

      await container.read(aiChatProvider.notifier).send('删掉那个模板');

      expect(invocations.length, 1, reason: '诚实失败不该被逼第二轮');
      expect(container.read(aiChatProvider).messages.last.content,
          contains('找不到'));
    });

    test('只读问答不补发', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '你这周练了 3 次'),
      ]);

      await container.read(aiChatProvider.notifier).send('我这周练了几次');

      expect(invocations.length, 1);
    });

    test('补发上限：连续两轮都不调工具 → 放行原文，不死循环', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '好嘞，弄好了'),
        const AiChatRoundResult(content: '好啦，已经加进去了'),
      ]);

      await container.read(aiChatProvider.notifier).send('帮我记录今天的训练');

      expect(invocations.length, lessThanOrEqualTo(3),
          reason: '最多补发 1 次（共 2~3 轮），不能无限循环');
      final last = container.read(aiChatProvider).messages.last.content;
      expect(last, contains('已经加进去了'), reason: '第二轮后放行原文');
    });
  });
}
