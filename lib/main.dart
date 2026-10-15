import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/notification_service.dart';
import 'core/database/database.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();

  // 从数据库加载提醒和主题设置
  final db = AppDatabase();
  final settings = await (db.select(db.userSettings)..limit(1)).getSingleOrNull();

  runApp(
    ProviderScope(
      child: FitTrackApp(
        initialReminderEnabled: settings?.reminderEnabled ?? false,
        initialReminderHour: settings?.reminderHour ?? 8,
        initialReminderMinute: settings?.reminderMinute ?? 0,
        initialThemeMode: settings?.themeMode,
      ),
    ),
  );
}
