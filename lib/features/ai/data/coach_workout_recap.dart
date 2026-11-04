import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/database.dart'
    show CoachProactiveMessagesCompanion;
import 'package:fittrack/core/services/coach_weekly_facts.dart' show mondayOf;
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';

/// 主动消息的第二种 kind
const String kRecapKind = 'workout_recap';

/// 每周点评上限（内展，不推送）。高频训练者的容忍上限就在这里。
const int kWeeklyRecapCap = 2;

/// 点评的去重键：`recap:{workoutId}` —— 需要已落库的训练 id
String recapDedupeKey(int workoutId) => 'recap:$workoutId';

/// 点气泡后预填的问句（**不自动发送**：请求要花钱，用户可能想换个问法）
const String kRecapPrefill = '刚才那次训练你帮我看看';

/// 点评文案（**一律本地模板，不调模型**）。
///
/// 三条理由（PRD 决策 4）：① 保存训练后立刻要出，模型要 3~8 秒；
/// ② 高频用户一周 5 练就是 5 次付费调用，为一句"练得不错"不值；
/// ③ 训练刚结束是"收尾"，用户要一句话，不是一段话。
///
/// 红线与 `AiPromptBuilder._rules` 一致：不提消耗多少大卡、不承诺减重速度、
/// 不用"加油 / 坚持就是胜利"这类口号、不给医疗建议。
///
/// 时长不知道（null / 0）时**不生成** —— 文案里那个数字必须有出处，
/// 编一个"28 分钟"就是造假。
String? recapContentFor({
  required Set<String> exerciseCategories,
  required int? durationSec,
}) {
  if (durationSec == null || durationSec <= 0) return null;
  final minutes = durationSec ~/ 60;

  // 任一类型，<10 分钟
  if (durationSec < 10 * 60) {
    return '10 分钟也算练了。这周要是还能挤出一次，就很好。';
  }

  // 有氧类（且没有力量动作）：PRD 定稿是"跑了 N 分钟"，但这一档也可能来自
  // 跳绳 / 骑车 / 椭圆机，说"跑了"是事实错误 —— 改成"有氧"。
  final cardioOnly =
      exerciseCategories.contains('cardio') && !exerciseCategories.contains('strength');
  if (cardioOnly) {
    return '有氧 $minutes 分钟，这个量对减脂够用了。今天别再加练，吃够蛋白就行。';
  }

  // 力量类，≥20 分钟
  if (durationSec >= 20 * 60) {
    return '刚那 $minutes 分钟力量练得挺实在。明天腿要是酸，就散散步，别硬上。';
  }

  // 10~20 分钟的普通训练：PRD 三条模板没覆盖这一档，按同一口径补一条
  // （只说"够了"，不估大卡、不承诺）
  return '刚那 $minutes 分钟练完了，记上了。今天的量够了，别急着加。';
}

/// 训练后点评的唯一入口。
///
/// 只在**首页咕嘎气泡**露出：训练完成页此刻的主按钮是「保存训练记录」，
/// 插一句话会挡住主路径；训练详情页再放一份等于同一句话两处各自处理已读。
class CoachWorkoutRecapService {
  CoachWorkoutRecapService({
    required CoachProactiveRepository repo,
    required UserSettingsRepository settings,
    DateTime Function()? now,
  })  : _repo = repo,
        _settings = settings,
        _now = now ?? DateTime.now;

  final CoachProactiveRepository _repo;
  final UserSettingsRepository _settings;
  final DateTime Function() _now;

  /// 训练保存成功后调用。返回 null = 本次不生成（开关关 / 本周已满 / 无可写文案）。
  ///
  /// 任何异常都吞掉：点评是锦上添花，绝不能把"已经保存成功的训练"拖成失败。
  Future<CoachProactiveMessage?> generateFor({
    required int workoutId,
    required Set<String> exerciseCategories,
    required int? durationSec,
  }) async {
    try {
      final settings = await _settings.get();
      // 总开关关 → 生成、推送、AI 调用全部为 0（PRD 决策 8）
      if (!(settings?.coachProactiveEnabled ?? true)) return null;

      final content = recapContentFor(
        exerciseCategories: exerciseCategories,
        durationSec: durationSec,
      );
      if (content == null) return null;

      final now = _now();
      final dayStart = DateTime(now.year, now.month, now.day);
      final tomorrow = dayStart.add(const Duration(days: 1));
      final key = recapDedupeKey(workoutId);

      // 同一天只留 1 条：第二次训练覆盖第一条（一天练两次的人不该收到两条）
      final today = await _repo.listKindBetween(
        kind: kRecapKind,
        from: dayStart,
        to: tomorrow,
      );
      if (today.any((m) => m.dedupeKey == key)) return today.first; // 重复保存
      if (today.isNotEmpty) {
        await _repo.deleteByDedupeKeys(today.map((m) => m.dedupeKey));
      }

      // 每周最多 2 条（今天的旧条已删掉，这里数的是本周剩下的）
      final weekStart = mondayOf(now);
      final thisWeek = await _repo.countKindBetween(
        kind: kRecapKind,
        from: weekStart,
        to: weekStart.add(const Duration(days: 7)),
      );
      if (thisWeek >= kWeeklyRecapCap) return null;

      return await _repo.insertIfAbsent(CoachProactiveMessagesCompanion.insert(
        kind: kRecapKind,
        dedupeKey: key,
        content: content,
        // 恒为 template：点评不走模型（PRD 决策 4）
        source: 'template',
        workoutId: Value(workoutId),
        // 显式写入：created_at 是"当日 / 本周"两个频率判定的唯一依据，
        // 依赖 DB 默认值(currentDateAndTime) 会让注入时钟与落库时钟分叉。
        createdAt: Value(now),
      ));
    } catch (e) {
      debugPrint('训练后点评生成失败（不影响训练保存）: $e');
      return null;
    }
  }

  /// 气泡渲染即已读（不推送，所以不需要 cancel 任何通知）
  Future<void> markSeen(int id) async {
    try {
      await _repo.markSeen(id, _now());
    } catch (e) {
      debugPrint('点评标记已读失败: $e');
    }
  }
}
