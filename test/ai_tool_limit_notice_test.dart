import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_round.dart';

/// 教练静默卡死：超限时必须**告诉用户**为什么停、下一步怎么做
void main() {
  group('上限常量', () {
    test('maxCallsPerRound = 12（建模板 + 批量补建动作的正常上限）', () {
      expect(AiToolLimits.maxCallsPerRound, 12);
    });

    test('用户提示同时包含"为什么停"和"下一步"', () {
      final msg = AiToolLimits.userLimitNotice(12);
      expect(msg, contains('有点多'));
      expect(msg, contains('继续'));
    });

    test('给模型的回执注明已告知用户', () {
      expect(AiToolLimits.overLimitMessage, contains('已告知用户'));
    });
  });

  group('状态机：超限不再静默', () {
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

    test('一次请求带 13 个只读调用 → 停在第 12 个，并留一条可见消息', () async {
      // 13 个 query_stats（只读，不会弹确认卡）
      rounds.add(AiChatRoundResult(toolCalls: [
        for (var i = 0; i < 13; i++)
          AiToolCall(
              id: 'c$i', name: 'query_stats', argumentsJson: '{"range":"week"}'),
      ]));

      await container.read(aiChatProvider.notifier).send('给我一堆统计');

      final state = container.read(aiChatProvider);
      // ① 不再转圈
      expect(state.isStreaming, isFalse);
      // ② 有一条含「继续」的 assistant 消息
      final notices =
          state.messages.where((m) => m.role == 'assistant' && '${m.content}'.contains('继续'));
      expect(notices, isNotEmpty, reason: '超限必须留下可见说明，不能静默');
      // ③ 不再发起新请求（只因首轮请求调用了一次 runner）
      expect(invocations, hasLength(1), reason: '超限后不该再自动请求下一轮');
    });
  });
}
