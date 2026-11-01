import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/coach_memory_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_extractor.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/presentation/notifiers/coach_memory_notifier.dart';

/// 抽取器（单测可 override 成假实现）
final coachMemoryExtractorProvider = Provider<CoachMemoryExtractor>((ref) {
  return CoachMemoryExtractor();
});

/// 记忆的唯一入口：注入 / 抽取 / 增删清
final coachMemoryServiceProvider = Provider<CoachMemoryService>((ref) {
  return CoachMemoryService(
    repo: ref.watch(coachMemoryRepoProvider),
    extractor: ref.watch(coachMemoryExtractorProvider),
    settings: ref.watch(userSettingsRepoProvider),
  );
});

/// 「教练记得的事」列表 —— 记忆页唯一数据源。
///
/// 用 AsyncNotifier（而不是 FutureProvider）是因为这张页有 4 种写操作
/// （删 / 撤销 / 清空 / 开关），每次写完都要立刻回读落 state；靠 invalidate
/// 会因为"删完还没重算就 pop 回去"闪一帧旧数据。
final coachMemoryListProvider =
    AsyncNotifierProvider<CoachMemoryNotifier, List<CoachMemory>>(
        CoachMemoryNotifier.new);
