import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/database/database.dart'
    show CoachProactiveMessagesCompanion;
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/core/services/coach_weekly_push.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';

// 「怎么生成」「推不推」都在 coach_weekly_push.dart（纯函数 + 假落点接口），
// 这里只剩「什么时候调它们」。两件事分文件，W5~W14 才能在无库无插件的单测里证伪。
export 'package:fittrack/core/services/coach_weekly_push.dart';

/// 主动消息的唯一入口：「生成」与「推送」彻底分离。
///
/// - 生成只依赖本地数据 + 一次可选 AI 调用；
/// - 推送只依赖一个纯函数决策。
///
/// 这样 W5/W6/W7/W13/W14 五条规则全部可以在**没有数据库、没有通知插件**的
/// 纯单测里证伪。
class CoachProactiveScheduler {
  CoachProactiveScheduler({
    required CoachProactiveRepository repo,
    required WeeklyFactLoader facts,
    required CoachWeeklyGenerator generator,
    required CoachPushSink push,
    required UserSettingsRepository settings,
    required DailyOverrideRepository overrides,
    DateTime Function()? now,
  })  : _repo = repo,
        _facts = facts,
        _generator = generator,
        _push = push,
        _settings = settings,
        _overrides = overrides,
        _now = now ?? DateTime.now;

  final CoachProactiveRepository _repo;
  final WeeklyFactLoader _facts;
  final CoachWeeklyGenerator _generator;
  final CoachPushSink _push;
  final UserSettingsRepository _settings;
  final DailyOverrideRepository _overrides;
  final DateTime Function() _now;

  /// 单飞：并发调用共享同一个 Future。
  ///
  /// 真实场景是"冷启动后立刻切回前台"—— 两个入口几乎同时触发，不共享就
  /// 会两次取数、两次调模型（费用翻倍），只剩唯一键在最后兜底。
  Future<void>? _inFlight;

  Future<void> runStartup() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<void> _run() async {
    await ensureWeeklyGenerated();
    await syncPush();
  }

  /// 生成本周的周消息（已有记录则什么都不做，W2）。
  ///
  /// 任何异常都吞掉：写入失败下次启动钩子会再试，绝不影响启动。
  Future<void> ensureWeeklyGenerated() async {
    try {
      final settings = await _settings.get();
      // W13：总开关关 → 不生成、不调模型
      if (!(settings?.coachProactiveEnabled ?? true)) {
        await _push.cancel(kCoachWeeklyNotificationId);
        return;
      }
      final weekStart = mondayOf(_now());
      final key = weeklyDedupeKey(weekStart);
      if (await _repo.getByDedupeKey(key) != null) return;

      final facts = await _facts.load(now: _now());
      final draft = await _generator.build(
        facts: facts,
        settings: settings,
        apiKey: AiService.resolveKey(settings?.aiApiKey),
      );
      // 唯一键冲突 → 返回 null → 视为"已生成"，静默跳过
      await _repo.insertIfAbsent(CoachProactiveMessagesCompanion.insert(
        kind: 'weekly',
        dedupeKey: key,
        content: draft.content,
        source: draft.source,
        weekStart: Value(weekStart),
      ));
    } catch (e) {
      debugPrint('周消息生成失败（不影响启动，下次钩子重试）: $e');
    }
  }

  /// 只做决策 + 排期/取消：**不生成、不调模型**（可反复调用，成本为零）。
  ///
  /// ⚠️ 任何走 `ReminderScheduler.reschedule()`（它第一步 `cancelAll()`）或
  /// `NotificationService().cancelAll()` 的路径之后，都必须再调一次这里，
  /// 否则 200 被一起清掉、周消息永远收不到且没有任何报错。
  Future<void> syncPush() async {
    try {
      final settings = await _settings.get();
      final enabled = settings?.coachProactiveEnabled ?? true;
      final now = _now();
      final weekStart = mondayOf(now);
      final record = await _repo.getWeekly(weekStart);
      // 没生成出东西就没得推（生成失败时留给下次启动钩子）
      if (!enabled || record == null) {
        await _push.cancel(kCoachWeeklyNotificationId);
        return;
      }
      final decision = decideWeeklyPush(
        now: now,
        weekStart: weekStart,
        reminderHour: settings?.reminderHour,
        enabled: enabled,
        seen: record.seenAt != null,
        pausedOnWeekStart: await _pausedOn(weekStart),
        fatigueSuppressed: isFatigueSuppressed(await _repo.recentWeekly()),
      );
      if (decision != CoachPushDecision.schedule) {
        await _push.cancel(kCoachWeeklyNotificationId);
        return;
      }
      await _push.schedule(
        id: kCoachWeeklyNotificationId,
        title: '嘎教练说',
        body: record.content,
        when: weeklyPushAt(
          weekStart: weekStart,
          reminderHour: settings?.reminderHour,
        ),
      );
    } catch (e) {
      debugPrint('周消息排期失败（不影响使用）: $e');
    }
  }

  /// 渲染即已读：写 `seen_at`（幂等）+ 撤掉已排的通知（W5 / W11）
  Future<void> markSeen(int id) async {
    try {
      await _repo.markSeen(id, _now());
      await _push.cancel(kCoachWeeklyNotificationId);
    } catch (e) {
      debugPrint('周消息标记已读失败: $e');
    }
  }

  /// 周一那天是否被生病闸门暂停（W7）。
  ///
  /// 读不到 → **不推**（与提醒排期的容错方向相反：提醒读失败宁可多响一次，
  /// 周消息读失败就静默一天，因为"生病了还收到上周总结"比"少一条推送"更糟）。
  Future<bool> _pausedOn(DateTime day) async {
    try {
      final o = await _overrides.getByDate(day);
      return o?.reminderPaused ?? false;
    } catch (_) {
      return true;
    }
  }
}
