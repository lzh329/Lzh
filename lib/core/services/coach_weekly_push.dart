import 'package:http/http.dart' as http;

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/services/ai_oneshot_service.dart';
import 'package:fittrack/core/services/coach_weekly_facts.dart';
import 'package:fittrack/core/services/coach_weekly_prompt.dart';
import 'package:fittrack/core/services/coach_weekly_template.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 周消息的通知 id —— **200 段**（0–99 训练、100–199 称重、8888/9999 常驻）。
///
/// 只许用这个常量，不许在别处写 `200`：段位重复会让两类通知互相覆盖，
/// 而"训练提醒被周消息顶掉"这种事故用户根本描述不出来。
const int kCoachWeeklyNotificationId = 200;

/// 排期落点的抽象。
///
/// **不给 `ReminderSink` 加方法**：`test/sick_day_reminder_scheduler_test.dart`
/// 里有一个 fake `ReminderSink`，加抽象方法会让它立刻编译失败 —— 那是 T03 的
/// 回归锁，为了新功能去改它等于自己弄脏"T03 没退化"这条证据。
abstract class CoachPushSink {
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  });

  Future<void> cancel(int id);
}

/// 生产落点：转发给 [NotificationService]
class NotificationCoachPushSink implements CoachPushSink {
  NotificationCoachPushSink(this._ns);

  final NotificationService _ns;

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) {
    return _ns.scheduleCoachWeekly(id: id, title: title, body: body, when: when);
  }

  @override
  Future<void> cancel(int id) => _ns.cancelById(id);
}

/// 推送决策的结果（**纯函数产出，没有任何 IO**）
enum CoachPushDecision {
  schedule,

  /// W13 总开关关
  suppressDisabled,

  /// W5 用户已在 App 内看到
  suppressSeen,

  /// W6 已过该周周一 09:00（含周一 10:00 才打开、周二及以后）
  suppressLate,

  /// W7 周一 `reminderPaused`
  suppressPaused,

  /// W14 连续 2 条未读
  suppressFatigue,
}

/// 周消息的推送时刻：默认该周周一 09:00；称重提醒也在 9 点 → 顺延 10:00（W4）。
///
/// 只针对 `reminderHour == 9` 这一种撞车：9 点是称重提醒的默认值，撞上的概率
/// 最高；用户若把称重设成 10:00，则周消息仍在 09:00 —— 那是不同小时，
/// 不构成"同一小时两条"。
DateTime weeklyPushAt({required DateTime weekStart, required int? reminderHour}) =>
    DateTime(
      weekStart.year,
      weekStart.month,
      weekStart.day,
      reminderHour == kWeeklyPushHour ? kWeeklyPushHourShifted : kWeeklyPushHour,
    );

/// W14：最近 2 条周消息都未被看到 → 停推（仍生成、仍内展）
bool isFatigueSuppressed(List<CoachProactiveMessage> recentWeekly) {
  if (recentWeekly.length < 2) return false;
  return recentWeekly.take(2).every((m) => m.seenAt == null);
}

/// 推不推的**唯一判定**（W5/W6/W7/W13/W14 全部收敛在这里）。
///
/// 判定顺序有意义：开关 → 已读 → 迟到 → 生病 → 降频。前三条与用户无关
/// （状态既定），后两条才是"打扰与否"的判断。
CoachPushDecision decideWeeklyPush({
  required DateTime now,
  required DateTime weekStart,
  required int? reminderHour,
  required bool enabled,
  required bool seen,
  required bool pausedOnWeekStart,
  required bool fatigueSuppressed,
}) {
  if (!enabled) return CoachPushDecision.suppressDisabled;
  if (seen) return CoachPushDecision.suppressSeen;
  final pushAt = weeklyPushAt(weekStart: weekStart, reminderHour: reminderHour);
  if (!now.isBefore(pushAt)) return CoachPushDecision.suppressLate;
  if (pausedOnWeekStart) return CoachPushDecision.suppressPaused;
  if (fatigueSuppressed) return CoachPushDecision.suppressFatigue;
  return CoachPushDecision.schedule;
}

/// 生成结果：正文 + 来源（`ai` / `template`）
class WeeklyDraft {
  final String content;
  final String source;

  const WeeklyDraft({required this.content, required this.source});
}

/// 生成器：走 PRD 决策 1 的 5 级降级链，**任何一级失败都落模板**。
///
/// 不重试、不排队、不把错误写进 UI —— 用户不需要知道这次是 AI 还是模板，
/// 只需要周一早上真的收到一条真话。
class CoachWeeklyGenerator {
  CoachWeeklyGenerator({
    http.Client? client,
    Duration aiTimeout = kWeeklyAiTimeout,
  })  : _client = client,
        _aiTimeout = aiTimeout;

  final http.Client? _client;
  final Duration _aiTimeout;

  Future<WeeklyDraft> build({
    required WeeklyFacts facts,
    required UserSettingsEntity? settings,
    required String? apiKey,
  }) async {
    final fallback = WeeklyDraft(
      content: CoachWeeklyTemplate.render(facts),
      source: 'template',
    );
    // ① 无 Key → 模板（多数用户走这条，功能必须有兜底）
    if (apiKey == null || apiKey.trim().isEmpty) return fallback;

    // ② 超时 / 网络异常 / 401 / 余额不足 → AiOneShotService 返回 null → 模板
    final text = await AiOneShotService.complete(
      apiKey: apiKey,
      messages: CoachWeeklyPrompt.messages(facts: facts, settings: settings),
      maxTokens: kWeeklyAiMaxTokens,
      temperature: 0.6,
      timeout: _aiTimeout,
      client: _client,
    );
    if (text == null) return fallback;

    // ③④ 字数越界 / 命中禁用词 → 模板
    final trimmed = text.trim();
    if (!CoachWeeklyTemplate.isAcceptable(trimmed)) return fallback;

    // ⑤ 通过
    return WeeklyDraft(content: trimmed, source: 'ai');
  }
}

