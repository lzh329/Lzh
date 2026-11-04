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

/// 假完成拦截：模型宣称"已记录/已补记"但本轮没调工具 → 数据没写，
/// 状态机必须拦下来逼它真的执行（真机：补 11-02 训练记录，全程没确认卡）。
void main() {
  group('claimsCompletedAction 纯函数', () {
    test('完成态断言 → true', () {
      expect(claimsCompletedAction('已帮你补记 11 月 2 日的训练'), isTrue);
      expect(claimsCompletedAction('记好了'), isTrue);
      expect(claimsCompletedAction('已记录今天的体重'), isTrue);
      expect(claimsCompletedAction('已删除那条记录'), isTrue);
    });

    test('带条件 / 征询语气 → false（那是在问，不是在宣称完成）', () {
      expect(claimsCompletedAction('要不要我帮你记录一下？'), isFalse);
      expect(claimsCompletedAction('如果确认的话我就记录了'), isFalse);
      expect(claimsCompletedAction('我可以帮你补记，确认吗？'), isFalse);
    });

    test('普通回答 / 空串 → false', () {
      expect(claimsCompletedAction('今天也要记得喝水'), isFalse);
      expect(claimsCompletedAction(''), isFalse);
    });
  });

  group('状态机假完成拦截', () {
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

    test('第 1 轮空口宣称完成 → 补发第 2 轮，且那句没进消息历史', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '已帮你补记 11 月 2 日的训练'),
        const AiChatRoundResult(toolCalls: [
          AiToolCall(
            id: 'c1',
            name: 'log_workout',
            argumentsJson: '{"date":"2025-11-02","plan_name":"补记训练"}',
          ),
        ]),
        const AiChatRoundResult(content: '好的，需要你确认一下这条记录'),
      ]);

      await container.read(aiChatProvider.notifier).send('补记 11 月 2 日的训练');

      expect(invocations.length, greaterThanOrEqualTo(2),
          reason: '宣称完成却没调工具 → 必须补发一轮');
      final state = container.read(aiChatProvider);
      final all = state.messages.map((m) => m.content).join('\n');
      expect(all, isNot(contains('已帮你补记 11 月 2 日的训练')), reason: '假完成那句不能落库/显示');
      // 第 2 轮只到确认卡为止，不该再补发第 3 轮
      expect(invocations.length, lessThanOrEqualTo(3));
    });

    test('正常回答不触发补发', () async {
      rounds.addAll([
        const AiChatRoundResult(content: '今天也要记得喝水哦'),
      ]);

      await container.read(aiChatProvider.notifier).send('随便聊一句');

      expect(invocations.length, 1);
      expect(container.read(aiChatProvider).messages.last.content, '今天也要记得喝水哦');
    });
  });
}
