import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// P2 回归：`_request()` 里「取设置 / 取趋势 / 写库」抛非 [AiToolException]
/// 异常时，必须把 isStreaming 复位并给出错误文案，否则输入框被永久禁用
/// （isBusy 一直为 true，只能重启 App）。
///
/// 这里不做网络请求：取趋势的 provider 直接抛异常，请求在一进入网络之前
/// 就失败，正好命中「异常在 try 内 → 兜底 catch」这条路径。
void main() {
  const UserSettingsEntity settings =
      UserSettingsEntity(id: 1, aiApiKey: 'sk-test-notifier');

  /// 通知器 `_init()` 是构造函数里的异步动作，这里等它落地
  Future<void> waitFor(
    ProviderContainer container,
    bool Function() done,
  ) async {
    for (var i = 0; i < 100; i++) {
      if (done()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('等待超时：异步初始化没有在预期次数的 microtask 内完成');
  }

  ProviderContainer buildContainer(
    _FakeChatRepository repo, {
    Object? trendsError,
  }) {
    return ProviderContainer(
      overrides: [
        userSettingsProvider.overrideWith((ref) async => settings),
        aiChatRepoProvider.overrideWithValue(repo),
        trendsDataProvider.overrideWith((ref) async {
          if (trendsError != null) throw trendsError;
          return const TrendsData();
        }),
      ],
    );
  }

  test('取趋势数据抛异常：send 不往外冒泡，isStreaming 复位且 error 有值', () async {
    final repo = _FakeChatRepository();
    final container = buildContainer(repo, trendsError: StateError('Drift 读库失败'));
    addTearDown(container.dispose);

    final notifier = container.read(aiChatProvider.notifier);
    await waitFor(container, () => container.read(aiChatProvider).hasKey);

    // 修复前：StateError 从 _request 冒泡 → 整个 send 抛异常，state 仍是
    // isStreaming=false/error=null，UI 无任何提示
    await notifier.send('今天晚饭吃什么');

    final state = container.read(aiChatProvider);
    expect(state.isStreaming, isFalse, reason: '异常后必须复位，否则输入框永久禁用');
    expect(state.isBusy, isFalse);
    expect(state.streamingText, isEmpty, reason: '失败后不残留半截流式文本');
    expect(state.error, '出错了，请稍后再试');
  });

  test('请求失败后仍能继续发送 / 重试（isBusy 未被卡死）', () async {
    final repo = _FakeChatRepository();
    final container = buildContainer(repo, trendsError: StateError('Drift 读库失败'));
    addTearDown(container.dispose);

    final notifier = container.read(aiChatProvider.notifier);
    await waitFor(container, () => container.read(aiChatProvider).hasKey);

    await notifier.send('第一句');
    expect(container.read(aiChatProvider).error, isNotNull);

    // 失败后第二次发送必须能进到写库（说明 isBusy 没有卡住 UI）
    await notifier.send('第二句');
    expect(repo.addCalls, ['user', 'user']);
    expect(container.read(aiChatProvider).isStreaming, isFalse);
    expect(container.read(aiChatProvider).error, '出错了，请稍后再试');

    // 重试同样不能抛出去，且仍然复位
    await notifier.retryLast();
    expect(container.read(aiChatProvider).isStreaming, isFalse);
    expect(container.read(aiChatProvider).error, '出错了，请稍后再试');
  });

  test('取设置抛异常：同样被兜底捕获，不冒泡到 UI', () async {
    final repo = _FakeChatRepository();
    final container = ProviderContainer(
      overrides: [
        // 首次（_init）成功，第二次（_request 内）失败
        userSettingsProvider.overrideWith((ref) async {
          if (ref.watch(_settingsCallCounterProvider) >= 1) {
            throw StateError('设置表读不出来');
          }
          return settings;
        }),
        aiChatRepoProvider.overrideWithValue(repo),
        trendsDataProvider.overrideWith((ref) async => const TrendsData()),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(aiChatProvider.notifier);
    await waitFor(container, () => container.read(aiChatProvider).hasKey);

    container.read(_settingsCallCounterProvider.notifier).state = 1;

    await notifier.send('配置读不出来的情况下发一句');

    final state = container.read(aiChatProvider);
    expect(state.isStreaming, isFalse);
    expect(state.error, '出错了，请稍后再试');
  });
}

/// 让 [userSettingsProvider] 的覆写可以「第一次成功、之后失败」
final _settingsCallCounterProvider = StateProvider<int>((ref) => 0);

/// 全文件共用一个 [AppDatabase] 占位实例（避免 drift 的「重复创建」告警）。
/// 它是 LazyDatabase，只要不发起查询就不会打开 sqlite 文件。
final AppDatabase _sharedDatabase = AppDatabase();

/// 内存版聊天仓库：不碰真实数据库，只记录调用
class _FakeChatRepository extends AiChatRepository {
  _FakeChatRepository() : super(_sharedDatabase);

  final List<AiMessage> stored = <AiMessage>[];
  final List<String> addCalls = <String>[];

  @override
  Future<List<AiMessage>> getHistory() async => List<AiMessage>.from(stored);

  @override
  Future<void> add(String role, String content) async {
    addCalls.add(role);
    stored.add(AiMessage(role: role, content: content));
  }

  @override
  Future<void> clear() async {
    stored.clear();
    addCalls.clear();
  }
}
