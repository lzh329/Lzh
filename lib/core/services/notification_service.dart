import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Android 13+ 通知权限请求
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> scheduleWorkoutReminder({
    required int id,
    required String planName,
    required String dayLabel,
    required int hour,
    required int minute,
    required int dayOfWeek,
  }) async {
    await _plugin.cancel(id);

    // 计算下一次该星期几的触发时间
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = _nextWeekday(now, dayOfWeek, hour, minute);

    await _plugin.zonedSchedule(
      id,
      '训练提醒',
      '今天($dayLabel)有训练计划「$planName」，别忘了锻炼！',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'workout_reminder',
          '训练提醒',
          channelDescription: '提醒你按时完成训练计划',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 每日称重提醒（每天重复）
  Future<void> scheduleDailyWeighInReminder({
    required int id,
    required int hour,
    required int minute,
  }) async {
    await _plugin.cancel(id);

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      '⏰ 该称重了',
      '打开减肥嘎记录今日体重，查看减脂进展 📉',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'weigh_in_reminder',
          '称重提醒',
          channelDescription: '每天提醒你称重记录体重',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// 录入体重后即时反馈通知
  Future<void> showWeightFeedback({
    required double currentWeightJin,
    double? changeJin,
    double? totalLossJin,
  }) async {
    final parts = <String>['今日体重 ${currentWeightJin.toStringAsFixed(1)} 斤'];

    String title = '📝 体重已记录';
    if (changeJin != null && changeJin < -0.05) {
      title = '📉 体重下降！';
      parts.add('较上次 ↓ ${changeJin.abs().toStringAsFixed(1)} 斤');
    } else if (changeJin != null && changeJin > 0.05) {
      title = '📊 体重已记录';
      parts.add('较上次 ↑ ${changeJin.toStringAsFixed(1)} 斤');
    } else if (changeJin != null) {
      parts.add('较上次持平');
    }

    if (totalLossJin != null && totalLossJin > 0.05) {
      parts.add('累计减重 ${totalLossJin.toStringAsFixed(1)} 斤 🎉');
    }

    await _plugin.show(
      9999, // 固定 ID，每次覆盖
      title,
      parts.join(' · '),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'weight_feedback',
          '体重反馈',
          channelDescription: '录入体重后的即时反馈',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  /// 训练进行中的常驻通知（锁屏 / 通知栏可见，切出去也能看到进度）
  ///
  /// ongoing + autoCancel=false：用户不能左滑划掉，训练结束由 App 主动取消。
  static const int workoutOngoingId = 8888;

  Future<void> showWorkoutOngoing({
    required String title,
    required String text,
  }) async {
    try {
      await _plugin.show(
        workoutOngoingId,
        title,
        text,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'workout_ongoing',
            '训练进行中',
            channelDescription: '训练时的常驻进度显示（锁屏/通知栏可见）',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showWhen: false,
            autoCancel: false,
          ),
          iOS: DarwinNotificationDetails(presentSound: false),
        ),
      );
    } catch (_) {
      // 通知权限被拒等情况静默失败，不影响训练本身
    }
  }

  Future<void> hideWorkoutOngoing() async {
    try {
      await _plugin.cancel(workoutOngoingId);
    } catch (_) {}
  }

  /// 取消单个通知（AI 教练关闭某类提醒时用，不影响其他排期）
  Future<void> cancelById(int id) async {
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  tz.TZDateTime _nextWeekday(
      tz.TZDateTime from, int targetWeekday, int hour, int minute) {
    // targetWeekday: 0=Sun, 1=Mon, ..., 6=Sat
    int currentWeekday = from.weekday %
        7; // DateTime.weekday: 1=Mon=1 ... 7=Sun=0, so %7 maps to 0=Sun
    int daysUntil = (targetWeekday - currentWeekday + 7) % 7;
    if (daysUntil == 0) {
      // 如果是今天且时间已过，推到下周
      final candidate = tz.TZDateTime(
          tz.local, from.year, from.month, from.day, hour, minute);
      if (candidate.isBefore(from)) daysUntil = 7;
    }
    final next = from.add(Duration(days: daysUntil));
    return tz.TZDateTime(
        tz.local, next.year, next.month, next.day, hour, minute);
  }
}
