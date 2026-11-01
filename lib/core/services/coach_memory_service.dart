import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/database/database.dart'
    show CoachMemoriesCompanion;
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/coach_memory_extractor.dart';
import 'package:fittrack/features/ai/data/coach_memory_repository.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/domain/coach_memory_policy.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';

/// 本轮记忆变更的结果（M12 的留痕只认这个对象）
class CoachMemoryWriteReport {
  final List<CoachMemory> added;
  final List<CoachMemory> updated;

  /// 被 forget 掉的（用 content 文案，删行后实体已不存在）
  final List<String> forgotten;

  /// 被上限淘汰的行数（不单独展示，只用于诊断）
  final int evicted;

  const CoachMemoryWriteReport({
    required this.added,
    required this.updated,
    required this.forgotten,
    required this.evicted,
  });

  /// 本轮没有任何变化 → 不留痕
  bool get isEmpty => added.isEmpty && updated.isEmpty && forgotten.isEmpty;

  /// 「右膝有旧伤 · 晚上十点后不吃东西」；超过 3 条时收口
  String get summary {
    final items = <String>[
      ...added.map((m) => m.content),
      ...updated.map((m) => m.content),
      ...forgotten,
    ];
    if (items.isEmpty) return '';
    if (items.length <= 3) return items.join(' · ');
    return '${items.take(3).join(' · ')} 等 ${items.length} 条';
  }
}

/// 记忆的唯一入口：抽取编排 + 注入行生成 + 开关判定 + 可见可删可清。
///
/// 三条失败策略（PRD 共享知识 3）：注入失败 → 空列表（绝不打断对话）；
/// 抽取 / 写入失败 → 吞异常只 `debugPrint`；开关关 → 三段全部短路。
class CoachMemoryService {
  CoachMemoryService({
    required CoachMemoryRepository repo,
    required CoachMemoryExtractor extractor,
    required UserSettingsRepository settings,
    DateTime Function()? now,
  })  : _repo = repo,
        _extractor = extractor,
        _settings = settings,
        _now = now ?? DateTime.now;

  final CoachMemoryRepository _repo;
  final CoachMemoryExtractor _extractor;
  final UserSettingsRepository _settings;
  final DateTime Function() _now;

  /// 开关是否打开（读不到设置行按"开"处理，与默认值一致）
  Future<bool> enabled() async {
    try {
      return (await _settings.get())?.coachMemoryEnabled ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 注入用：≤[limit] 行 `类目·内容`（默认 4 条）。
  ///
  /// 命中条目的 `last_used_at` 会被更新（M10）—— 那是后续淘汰的依据。
  /// 开关关 / 一条都没有 → 空列表（注入段整段不出现，不留空标题）。
  Future<List<String>> promptLines(
      {int limit = CoachMemoryPolicy.promptLimit}) async {
    try {
      if (!await enabled()) return const <String>[];
      final all = await _repo.listAll();
      if (all.isEmpty) return const <String>[];
      final picked = CoachMemoryPolicy.selectForPrompt(all, limit);
      if (picked.isEmpty) return const <String>[];
      await _repo.touch(picked.map((m) => m.id).toList(), _now());
      return picked.map((m) => m.promptLine).toList();
    } catch (e) {
      // 注入失败绝不影响对话：宁可这一轮没有记忆，也不能让用户发不出消息
      debugPrint('记忆注入失败（本轮不用记忆）: $e');
      return const <String>[];
    }
  }

  /// **只读**版本：与 [promptLines] 同一套挑选，但**不更新 `last_used_at`**。
  ///
  /// 「人设文案」页的提示词预览用它。预览只是让用户看一眼 prompt 长什么样，
  /// 不该改变"哪条记忆最近被用过" —— 那会污染 M9 的淘汰顺序：用户点两次预览，
  /// 就能把某条记忆刷成"最新用过"，从此永远不被淘汰。
  Future<List<String>> readOnlyLines({
    int limit = CoachMemoryPolicy.promptLimit,
  }) async {
    try {
      if (!await enabled()) return const <String>[];
      final all = await _repo.listAll();
      if (all.isEmpty) return const <String>[];
      return CoachMemoryPolicy.selectForPrompt(all, limit)
          .map((m) => m.promptLine)
          .toList();
    } catch (e) {
      debugPrint('记忆只读预览失败（预览不显示记忆段）: $e');
      return const <String>[];
    }
  }

  /// 一轮对话正常结束后的唯一入口。返回 null = 本轮没有任何变化（不留痕）。
  Future<CoachMemoryWriteReport?> extractAndApply({
    required List<String> userTurns,
    required String currentUserText,
    int? sourceMessageId,
  }) async {
    try {
      if (!await enabled()) return null; // M15：关掉就不写、不留痕
      final settings = await _settings.get();
      final apiKey = AiService.resolveKey(settings?.aiApiKey);
      if (apiKey == null) return null; // 没有 Key 就没有对话，也就不需要记忆

      final haystack = [...userTurns, currentUserText].join('\n');
      var all = await _repo.listAll();
      final candidates = await _extractor.extract(
        userTurns: userTurns,
        currentUserText: currentUserText,
        existing: all,
        apiKey: apiKey,
      );
      if (candidates.isEmpty) return null;

      final added = <CoachMemory>[];
      final updated = <CoachMemory>[];
      final forgotten = <String>[];
      var evicted = 0;

      for (final c in candidates) {
        final reason = CoachMemoryPolicy.validate(c, haystack);
        if (reason != null) {
          // 丢弃比落库好：一条编造的记忆会污染后面所有轮次
          debugPrint('记忆候选被丢弃（$reason）: ${c.category}/${c.topic}');
          continue;
        }
        final topic = CoachMemoryPolicy.normalizeTopic(c.topic)!;

        if (c.isForget) {
          CoachMemory? hit;
          for (final m in all) {
            if (m.category == c.category && m.topic == topic) {
              hit = m;
              break;
            }
          }
          if (hit == null) continue; // 不存在 → 不报错、不计数（M6）
          final ok = await _repo.deleteByKey(c.category, topic);
          if (!ok) continue;
          forgotten.add(hit.content);
          all = all
              .where((m) => !(m.category == c.category && m.topic == topic))
              .toList();
          continue;
        }

        if (CoachMemoryPolicy.shouldSkipInsert(
          all: all,
          incomingCategory: c.category,
        )) {
          continue;
        }
        for (final id in CoachMemoryPolicy.evictionsNeeded(
          all: all,
          incomingCategory: c.category,
        )) {
          await _repo.deleteById(id);
          evicted++;
          all = all.where((m) => m.id != id).toList();
        }

        final existed =
            all.any((m) => m.category == c.category && m.topic == topic);
        final saved = await _repo.upsert(CoachMemoriesCompanion.insert(
          category: c.category,
          topic: topic,
          content: c.content.trim(),
          quote: c.quote.trim(),
          sourceMessageId: Value(sourceMessageId),
          updatedAt: Value(_now()),
          createdAt: Value(_now()),
        ));
        if (saved == null) continue;
        if (existed) {
          updated.add(saved);
          all = all
              .map((m) =>
                  (m.category == saved.category && m.topic == saved.topic)
                      ? saved
                      : m)
              .toList();
        } else {
          added.add(saved);
          all = [...all, saved];
        }
      }

      if (added.isEmpty && updated.isEmpty && forgotten.isEmpty) return null;
      return CoachMemoryWriteReport(
        added: added,
        updated: updated,
        forgotten: forgotten,
        evicted: evicted,
      );
    } catch (e) {
      // 锦上添花不能卡住主流程（与 T03「计数写失败不许影响撤销」同思路）
      debugPrint('记忆写入失败（不影响对话）: $e');
      return null;
    }
  }

  Future<List<CoachMemory>> listAll() async {
    try {
      return await _repo.listAll();
    } catch (_) {
      return const <CoachMemory>[];
    }
  }

  Future<int> count() async {
    try {
      return await _repo.count();
    } catch (_) {
      return 0;
    }
  }

  /// 删单条并返回被删的行（M14 的 5 秒撤销要用它）
  Future<CoachMemory?> deleteById(int id) => _repo.deleteById(id);

  Future<void> restore(CoachMemory m) => _repo.reinsert(m);

  /// 「清除全部记忆」（M16，二次确认由页面负责）
  Future<int> clearAll() => _repo.deleteAll();
}
