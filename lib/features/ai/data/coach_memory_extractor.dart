import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:fittrack/features/ai/data/ai_oneshot_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_prompt.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';

/// 一次轻量模型调用：把「最近几轮用户原话」压成结构化候选。
///
/// 参数口径（PRD 决策 5 / 8.3）：`maxTokens=600`、`temperature=0.2`、
/// 超时 15 秒、**不重试**、失败静默返回空列表。
///
/// 这里**不做语义校验** —— 白名单、quote 子串、长度、数字拦截都在
/// `CoachMemoryPolicy`。抽取器的职责只有"把模型的话翻译成候选对象"。
class CoachMemoryExtractor {
  CoachMemoryExtractor({
    http.Client? client,
    Duration timeout = kMemoryExtractTimeout,
  })  : _client = client,
        _timeout = timeout;

  final http.Client? _client;
  final Duration _timeout;

  static const int maxTokens = 600;
  static const double temperature = 0.2;

  /// 任何异常 / 非 JSON / 非数组 → 返回空列表（失败静默，绝不影响对话）
  Future<List<CoachMemoryCandidate>> extract({
    required List<String> userTurns,
    required String currentUserText,
    required List<CoachMemory> existing,
    required String? apiKey,
  }) async {
    if (apiKey == null || apiKey.trim().isEmpty) return const [];
    if (userTurns.isEmpty && currentUserText.trim().isEmpty) return const [];

    final raw = await AiOneShotService.complete(
      apiKey: apiKey,
      messages: CoachMemoryPrompt.messages(
        userTurns: userTurns,
        existing: existing,
      ),
      maxTokens: maxTokens,
      temperature: temperature,
      timeout: _timeout,
      client: _client,
    );
    if (raw == null) return const [];

    final items = CoachMemoryPrompt.parseCandidates(raw);
    if (items.isEmpty) return const [];

    final out = <CoachMemoryCandidate>[];
    for (final item in items) {
      final category = (item['category'] as String?)?.trim().toLowerCase() ?? '';
      final action =
          (item['action'] as String?)?.trim().toLowerCase() ?? 'remember';
      out.add(CoachMemoryCandidate(
        action: action,
        category: category,
        topic: (item['topic'] as String?) ?? '',
        content: (item['content'] as String?) ?? '',
        quote: (item['quote'] as String?) ?? '',
        confidence: (item['confidence'] as num?)?.toDouble() ?? 0.5,
      ));
    }
    debugPrint('记忆抽取返回 ${out.length} 条候选');
    return out;
  }
}

/// 记忆抽取的超时（PRD「记忆抽取超时（15s）→ 放弃本轮，不重试」）
const Duration kMemoryExtractTimeout = Duration(seconds: 15);
