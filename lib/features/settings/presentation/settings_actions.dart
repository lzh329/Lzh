import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';

/// 设置页的操作逻辑集合（从原 settings_page.dart 抽出，保持行为不变）

Future<String?> showPinSetupDialog(BuildContext context) async {
  final pinCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  String? result;

  await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('设置 PIN 码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '输入 4 位 PIN 码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: confirmCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '再次输入 PIN 码',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final pin = pinCtrl.text;
            if (pin.length != 4 || pin != confirmCtrl.text) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('PIN 码不匹配或不足 4 位')),
              );
              return;
            }
            result = pin;
            Navigator.pop(ctx);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
  return result;
}

Future<void> scheduleReminders(WidgetRef ref) async {
  if (!ref.read(reminderEnabledProvider)) return;
  final hour = ref.read(reminderHourProvider);
  final minute = ref.read(reminderMinuteProvider);
  final planRepo = ref.read(planRepoProvider);
  final plans = await planRepo.getAll();
  final activePlans = plans.where((p) => p.isActive).toList();
  final ns = NotificationService();

  await ns.cancelAll();
  int id = 0;

  if (activePlans.isEmpty) {
    for (int d = 0; d < 7; d++) {
      await ns.scheduleWorkoutReminder(
        id: id++,
        planName: '每日训练',
        dayLabel: '',
        hour: hour,
        minute: minute,
        dayOfWeek: d,
      );
    }
  } else {
    for (final plan in activePlans) {
      for (final day in plan.days) {
        await ns.scheduleWorkoutReminder(
          id: id++,
          planName: plan.name,
          dayLabel: PlanDayEntity.dayLabels[day.dayOfWeek],
          hour: hour,
          minute: minute,
          dayOfWeek: day.dayOfWeek,
        );
      }
    }
  }

  // 每日称重提醒（id 从 100 开始，避免与训练提醒冲突）
  for (int d = 0; d < 7; d++) {
    await ns.scheduleDailyWeighInReminder(
      id: 100 + d,
      hour: hour,
      minute: minute,
    );
  }
}

Future<void> pickReminderTime(BuildContext context, WidgetRef ref) async {
  final hour = ref.read(reminderHourProvider);
  final minute = ref.read(reminderMinuteProvider);
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: hour, minute: minute),
  );
  if (time != null) {
    ref.read(reminderHourProvider.notifier).state = time.hour;
    ref.read(reminderMinuteProvider.notifier).state = time.minute;
    await ref.read(userSettingsRepoProvider).save(
          reminderHour: time.hour,
          reminderMinute: time.minute,
        );
    await scheduleReminders(ref);
  }
}

Future<void> exportWorkouts(BuildContext context, WidgetRef ref) async {
  try {
    final repo = ref.read(workoutRepoProvider);
    final workouts = await repo.getAll();
    if (workouts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无训练记录可导出')),
        );
      }
      return;
    }

    final buf = StringBuffer();
    buf.writeln('日期,类型,动作数,组数');
    for (final w in workouts) {
      final exerciseIds = w.sets.map((s) => s.exerciseId).toSet();
      buf.writeln(
        '${DateFormat('yyyy-MM-dd HH:mm').format(w.date)},${w.type},${exerciseIds.length},${w.totalSets}',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/fittrack_workouts_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
    );
    await file.writeAsString(buf.toString());

    await Share.shareXFiles([XFile(file.path)], text: 'FitTrack 训练记录导出');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }
}

Future<void> exportBodyMetrics(BuildContext context, WidgetRef ref) async {
  try {
    final repo = ref.read(bodyMetricRepoProvider);
    final metrics = await repo.getAll();
    if (metrics.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('暂无身体数据可导出')),
        );
      }
      return;
    }

    final buf = StringBuffer();
    buf.writeln('日期,体重(斤),腰围(cm),臀围(cm),胸围(cm),备注');
    for (final m in metrics) {
      buf.writeln(
        '${DateFormat('yyyy-MM-dd').format(m.date)},${(m.weightKg * 2).toStringAsFixed(1)},${m.waistCm ?? ''},${m.hipCm ?? ''},${m.chestCm ?? ''},${m.note ?? ''}',
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/fittrack_body_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
    );
    await file.writeAsString(buf.toString());

    await Share.shareXFiles([XFile(file.path)], text: 'FitTrack 身体数据导出');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }
}

Future<void> backupDatabase(BuildContext context) async {
  try {
    final dbPath = await getDbPath();
    final backupDir = Directory('/storage/emulated/0/Download');
    if (!await backupDir.exists()) {
      final dir = await getApplicationDocumentsDirectory();
      final backupFile = File(
        '${dir.path}/fittrack_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.sqlite',
      );
      await File(dbPath).copy(backupFile.path);
      await Share.shareXFiles([XFile(backupFile.path)], text: 'FitTrack 数据库备份');
    } else {
      final backupFile = File(
        '${backupDir.path}/fittrack_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.sqlite',
      );
      await File(dbPath).copy(backupFile.path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已保存到 ${backupFile.path}')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('备份失败: $e')),
      );
    }
  }
}

Future<void> restoreDatabase(BuildContext context) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final backupFile = File('${dir.path}/fittrack_backup_latest.sqlite');

    if (!await backupFile.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('未找到备份文件，请先备份或放入 fittrack_backup_latest.sqlite 到应用目录'),
          ),
        );
      }
      return;
    }

    final dbPath = await getDbPath();
    await backupFile.copy(dbPath);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('数据库已恢复，请重启应用')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('恢复失败: $e')),
      );
    }
  }
}

Future<String> getDbPath() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  return '${dbFolder.path}/fittrack.sqlite';
}
