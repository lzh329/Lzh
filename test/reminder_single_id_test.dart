import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/reminder_scheduler.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';
import 'package:drift/native.dart';

/// 「到点不推送」的三个断点里，能单测的那个：**双轨重复排期**。
///
/// manifest 权限与 receiver、tz.local 属于平台/环境层，无法单测，
/// 走报告里的人工验收步骤。
void main() {
  late AppDatabase db;
  late _RecordingSink sink;
  late ReminderScheduler scheduler;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    sink = _RecordingSink();
    scheduler = ReminderScheduler(
      sink: sink,
      gate: SickDayGate(
          DailyOverrideRepository(db), UserSettingsRepositoryImpl(db)),
    );
  });

  tearDown(() async => db.close());

  test('排期只产生 1 条每日称重通知，id 是 kWeighInReminderId', () async {
    await scheduler.reschedule(
      enabled: true,
      hour: 9,
      minute: 0,
      workoutSlots: const [],
      weighInId: kWeighInReminderId,
    );

    expect(sink.scheduledWeighInIds, [kWeighInReminderId],
        reason: '以前 100~106 各排一条 = 同一时刻每天弹 7 条');
  });

  test('重排时清掉历史遗留的 101~106（老用户设备上它们还活着）', () async {
    await scheduler.reschedule(
      enabled: true,
      hour: 9,
      minute: 0,
      workoutSlots: const [],
      weighInId: kWeighInReminderId,
    );

    expect(
      sink.cancelledIds,
      containsAll([101, 102, 103, 104, 105, 106]),
      reason: '只 cancel 新 id 的话，老排期会继续每天多弹 6 条',
    );
  });

  test('AI 路径（rescheduleWeighInOnly）排到的 id 与设置页路径一致', () async {
    await scheduler.reschedule(
      enabled: true,
      hour: 9,
      minute: 0,
      workoutSlots: const [],
      weighInId: kWeighInReminderId,
    );
    final settingsPageIds = [...sink.scheduledWeighInIds];

    sink.reset();
    await scheduler.rescheduleWeighInOnly(
      enabled: true,
      hour: 21,
      minute: 30,
    );

    expect(sink.scheduledWeighInIds, settingsPageIds,
        reason: '两条路径必须落到同一个 id，否则又会分叉成两套排期');
    expect(sink.scheduledWeighInIds, [kWeighInReminderId]);
  });

  test('AI 关闭提醒 → 取消该 id 且不再排期', () async {
    await scheduler.rescheduleWeighInOnly(
      enabled: false,
      hour: 9,
      minute: 0,
    );
    expect(sink.scheduledWeighInIds, isEmpty);
    expect(sink.cancelledIds, contains(kWeighInReminderId));
  });

  test('kLegacyWeighInReminderIds 覆盖 100~106（清理清单不能漏 id）', () {
    expect(kLegacyWeighInReminderIds, [100, 101, 102, 103, 104, 105, 106]);
    expect(kLegacyWeighInReminderIds, contains(kWeighInReminderId));
  });
}

class _RecordingSink implements ReminderSink {
  final List<int> scheduledWeighInIds = [];
  final List<int> cancelledIds = [];

  void reset() {
    scheduledWeighInIds.clear();
    cancelledIds.clear();
  }

  @override
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) async {
    scheduledWeighInIds.add(id);
  }

  @override
  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) async {}

  @override
  Future<void> cancelById(int id) async => cancelledIds.add(id);

  @override
  Future<void> cancelAll() async {}
}
