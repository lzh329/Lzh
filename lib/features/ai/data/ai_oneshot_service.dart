import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:fittrack/features/ai/data/ai_service.dart';

/// 「问一句、拿一段」的轻量模型调用的唯一入口。
///
/// 周消息正文与记忆抽取都需要"一次请求、一段文本、不需要工具、不需要多轮"，
/// 而 [AiService] 只暴露了面向对话的 `streamChat`。这里基于它做一层薄包装：
/// 忽略逐段回调、只取最终正文 —— 好处是**只有一份请求构造代码**
/// （模型名 / thinking 关闭 / max_tokens / 错误文案全在 AiService 里），
/// 不会出现"周消息那次调用忘了关 thinking 于是工具回合 400"这类分叉。
///
/// 三条硬规矩（PRD 决策 1 / 决策 5 / 第八章）：
/// 1. **失败静默**：返回 null，不抛异常、不重试、不给用户看错误 ——
///    周消息要落模板，记忆抽取直接放弃本轮，两者都不该让主流程感知。
/// 2. **超时 15 秒**：生成发生在启动 / 回前台钩子上，卡住会拖慢首屏。
/// 3. **token 上限**：默认 600，调用方按需下调（周消息 300）。
class AiOneShotService {
  AiOneShotService._();

  /// 记忆抽取的 token 上限（周消息传 300）
  static const int defaultMaxTokens = 600;

  /// 默认超时：与 PRD「本轮生成超时（15 秒）」逐字一致
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// 一次性补全。任何失败都返回 null（含空正文）。
  ///
  /// [client] 仅测试注入 —— 生产走 `AiService` 内部自建 client。
  static Future<String?> complete({
    required String apiKey,
    required List<AiMessage> messages,
    int maxTokens = defaultMaxTokens,
    double temperature = 0.2,
    Duration timeout = defaultTimeout,
    http.Client? client,
  }) async {
    if (apiKey.trim().isEmpty || messages.isEmpty) return null;
    try {
      final result = await AiService.streamChat(
        apiKey: apiKey,
        messages: messages,
        // 一次性调用不关心打字机效果，逐段回调直接丢弃
        onDelta: (_) {},
        temperature: temperature,
        maxTokens: maxTokens,
        client: client,
      ).timeout(timeout);
      final text = result.content.trim();
      return text.isEmpty ? null : text;
    } on TimeoutException {
      debugPrint('一次性模型调用超时（${timeout.inSeconds} 秒），放弃本轮（不重试）');
      return null;
    } catch (e) {
      // 网络异常 / 401 / 余额不足 / 400：全部静默。调用方各自有兜底
      // （周消息落模板、记忆抽取放弃本轮）。
      debugPrint('一次性模型调用失败（静默处理）: $e');
      return null;
    }
  }
}
