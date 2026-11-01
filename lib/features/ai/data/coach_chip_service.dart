import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/domain/coach_chip_rules.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';

/// 芯片生成的 IO 层：查「今日有没有对应记录」，然后交给纯函数判定。
///
/// 任何 IO 异常 → 返回空列表（PRD 第八章「芯片生成异常不影响消息本身」）。
/// 芯片是快捷键，缺了它用户顶多自己多点两下；但一次读库失败绝不能拖挂整条回复。
class CoachChipService {
  CoachChipService({
    required BodyMetricRepository body,
    required DietRepository diet,
    DateTime Function()? now,
  })  : _body = body,
        _diet = diet,
        _now = now ?? DateTime.now;

  final BodyMetricRepository _body;
  final DietRepository _diet;
  final DateTime Function() _now;

  /// [toolMessages] 是本轮的工具上下文（`AiToolContext.messages`）。
  ///
  /// 回执在这里拼成 `工具名:回执JSON`：`AiToolContext.failureReceipt()` 只产出
  /// `{"ok":false,"error":"..."}`，**不含工具名** —— 光看回执分不清是哪个工具
  /// 失败。这个约定属于芯片模块，所以拼装也放在这里，不要散到 notifier 里。
  Future<List<CoachChip>> buildFor({
    required String assistantText,
    required List<AiMessage> toolMessages,
  }) async {
    final receipts = <String>[
      for (final m in toolMessages)
        if (m.role == 'tool' && (m.toolName ?? '').isNotEmpty)
          '${m.toolName}:${m.textOnly}',
    ];
    try {
      final now = _now();
      // 必须归一到当天 0 点：`getAll(from, to)` 是按时刻比较的，
      // 传 now 会把"今天早上 8 点记的体重"漏掉（下午问就不算今天了）。
      final dayStart = DateTime(now.year, now.month, now.day);
      final weights = await _body.getAll(from: dayStart, to: dayStart);
      final calories = await _diet.getDailyCalories(dayStart);
      return CoachChipRules.build(
        assistantText: assistantText,
        toolReceipts: receipts,
        hasWeightToday: weights.isNotEmpty,
        hasFoodToday: calories > 0,
      );
    } catch (e) {
      debugPrint('芯片生成失败（本次不显示芯片）: $e');
      return const <CoachChip>[];
    }
  }
}
