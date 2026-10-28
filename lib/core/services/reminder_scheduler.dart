import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';

/// 训练提醒的排期槽位：一周里某一天的一条提醒。
class WorkoutReminderSlot {
  const WorkoutReminderSlot({
    required this.id,
    required this.planName,
    required this.dayLabel,
    required this.dayOfWeek,
  });

  final int id;
  final String planName;
  final String dayLabel;

  /// 0=周日 … 6=周六
  final int dayOfWeek;
}

/// 称重提醒的通知 id（100 段，避开训练提醒的 0 段）。
///
/// 与 `scheduleDailyWeighInReminder` 的历史用法保持一致：每天一条、共 7 个 id。
const List<int> kWeighInReminderIds = <int>[
  100,
  101,
  102,
  103,
  104,
  105,
  106,
];

/// 今天这条训练提醒该不该跳过（纯函数，T03-D1 / D3）。
///
/// **只跳今天那一条，其余星期几照排。** 提醒是按周重复的
/// （`matchDateTimeComponents: dayOfWeekAndTime`），所以「今天暂停」不能靠把
/// 首次触发时间往后挪 —— 那会改掉星期、破坏后续周期。今天那条不排，
/// 跨天后由 App 重排回来，这是唯一不破坏周期的做法。
bool skipsWorkoutReminderToday({
  required DateTime now,
  required int dayOfWeek,
  required bool pausedToday,
}) {
  if (!pausedToday) return false;
  return dayOfWeek == now.weekday % 7;
}

/// 由当前活跃计划推导训练提醒槽位（没有活跃计划 → 每天都排「每日训练」）。
///
/// 抽出来的理由：app.dart 的启动排期与设置页的改时间排期原本各写了一遍这个
/// 循环 —— 两处分开写必然分叉（改了一处忘了另一处，表现是"改了设置没生效"）。
List<WorkoutReminderSlot> buildWorkoutSlots(List<PlanEntity> plans) {
  final active = plans.where((p) => p.isActive).toList();

  if (active.isEmpty) {
    return [
      for (int d = 0; d < 7; d++)
        WorkoutReminderSlot(
          id: d,
          planName: '每日训练',
          dayLabel: '',
          dayOfWeek: d,
        ),
    ];
  }

  final slots = <WorkoutReminderSlot>[];
  var id = 0;
  for (final plan in active) {
    for (final day in plan.days) {
      slots.add(WorkoutReminderSlot(
        id: id++,
        planName: plan.name,
        dayLabel: PlanDayEntity.dayLabels[day.dayOfWeek],
        dayOfWeek: day.dayOfWeek,
      ));
    }
  }
  return slots;
}

/// 提醒排期的落点抽象。
///
/// 生产环境转发给 [NotificationService]；单测里换成记录调用的假实现 ——
/// 本地通知插件在单测进程里不可用，没有这层就没法断言「今天没排」。
abstract class ReminderSink {
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  });

  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  });

  Future<void> cancelById(int id);

  Future<void> cancelAll();
}

/// 真实落点：转发给 [NotificationService]。
class NotificationServiceSink implements ReminderSink {
  NotificationServiceSink(this._ns);

  final NotificationService _ns;

  @override
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) {
    return _ns.scheduleWorkoutReminder(
      id: id,
      planName: planName,
      dayLabel: dayLabel,
      hour: hour,
      minute: minute,
      dayOfWeek: dayOfWeek,
    );
  }

  @override
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) {
    return _ns.scheduleDailyWeighInReminder(id: id, hour: hour, minute: minute);
  }

  @override
  Future<void> cancelById(int id) => _ns.cancelById(id);

  @override
  Future<void> cancelAll() => _ns.cancelAll();
}

/// 提醒排期 + 生病闸门（`reminderPaused`）。
///
/// 闸门只管这两条提醒：**训练提醒 + 每日称重提醒**。
/// 本 App 没有喝水提醒（`NotificationService` 只有训练提醒、称重提醒、录入体重
/// 后反馈、训练常驻通知四种能力），别凭空加第三条。
class ReminderScheduler {
  ReminderScheduler({
    required this.sink,
    required this.gate,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ReminderSink sink;
  final SickDayGate gate;
  final DateTime Function() _now;

  /// 今天的提醒是否被闸门暂停。
  ///
  /// 两条同时成立才算暂停：当天存在覆盖 **且** 覆盖里 `reminderPaused` 为真。
  /// 覆盖存在但 `reminderPaused == false`（用户只想缩组数、不介意被提醒）→
  /// 照常响，别自作主张连提醒一起停。
  Future<bool> pausedToday() => _pausedAt(_now());

  /// 全量重排：先清干净旧的，再按今天的闸门状态逐条决定排不排。
  ///
  /// [enabled] 为 false（全局提醒开关关着）→ 一条都不排（T03-D6）。
  Future<void> reschedule({
    required bool enabled,
    required int hour,
    required int minute,
    required List<WorkoutReminderSlot> workoutSlots,
    required List<int> weighInIds,
  }) async {
    await sink.cancelAll();
    if (!enabled) return;

    final now = _now();
    final paused = await _pausedAt(now);

    for (final slot in workoutSlots) {
      if (skipsWorkoutReminderToday(
        now: now,
        dayOfWeek: slot.dayOfWeek,
        pausedToday: paused,
      )) {
        continue; // 今天这条不排 —— 上面 cancelAll 已经把之前排的取消了
      }
      await sink.scheduleWorkoutReminder(
        id: slot.id,
        planName: slot.planName,
        dayLabel: slot.dayLabel,
        hour: hour,
        minute: minute,
        dayOfWeek: slot.dayOfWeek,
      );
    }

    if (paused) return; // 称重提醒今天也不排（T03-D2）
    for (final id in weighInIds) {
      await sink.scheduleDailyWeighInReminder(
        id: id,
        hour: hour,
        minute: minute,
      );
    }
  }

  Future<bool> _pausedAt(DateTime now) async {
    try {
      final o = await gate.overrideFor(now);
      return o != null && o.reminderPaused;
    } catch (_) {
      // 闸门读不到（库未开 / 迁移中）→ 不暂停。
      // 宁可今天多响一次，也不能因为一次读库失败把提醒静音掉：
      // 多响用户能自己关，静音是用户看不见的。
      return false;
    }
  }
}
