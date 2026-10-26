import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/providers.dart';
import 'features/plan/domain/entities/plan_day_entity.dart';
import 'core/services/notification_service.dart';

class FitTrackApp extends ConsumerStatefulWidget {
  final bool initialReminderEnabled;
  final int initialReminderHour;
  final int initialReminderMinute;
  final String? initialThemeMode;

  const FitTrackApp({
    super.key,
    this.initialReminderEnabled = false,
    this.initialReminderHour = 8,
    this.initialReminderMinute = 0,
    this.initialThemeMode,
  });

  @override
  ConsumerState<FitTrackApp> createState() => _FitTrackAppState();
}

class _FitTrackAppState extends ConsumerState<FitTrackApp> {
  @override
  void initState() {
    super.initState();
    // 初始化提醒状态
    initReminderState(
      ref,
      enabled: widget.initialReminderEnabled,
      hour: widget.initialReminderHour,
      minute: widget.initialReminderMinute,
    );
    // 初始化主题模式
    initThemeMode(ref, themeMode: widget.initialThemeMode);
    // 如果提醒已启用，排入通知
    if (widget.initialReminderEnabled) {
      _scheduleOnStart();
    }
  }

  Future<void> _scheduleOnStart() async {
    final planRepo = ref.read(planRepoProvider);
    final plans = await planRepo.getAll();
    final activePlans = plans.where((p) => p.isActive).toList();
    final ns = NotificationService();
    final hour = ref.read(reminderHourProvider);
    final minute = ref.read(reminderMinuteProvider);

    await ns.cancelAll();
    int id = 0;

    if (activePlans.isEmpty) {
      // 无活跃计划时排一个每日提醒
      for (int d = 0; d < 7; d++) {
        ns.scheduleWorkoutReminder(
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
          ns.scheduleWorkoutReminder(
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
      ns.scheduleDailyWeighInReminder(id: 100 + d, hour: hour, minute: minute);
    }
  }

  @override
  Widget build(BuildContext context) {
    initializeDateFormatting('zh_CN');
    return _LockGate(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: MaterialApp.router(
          title: '减肥嘎',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          themeMode: ThemeMode.light,
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: appRouter,
        ),
      ),
    );
  }
}

class _LockGate extends ConsumerStatefulWidget {
  final Widget child;
  const _LockGate({required this.child});

  @override
  ConsumerState<_LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<_LockGate>
    with WidgetsBindingObserver {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkLock();
    if (state == AppLifecycleState.paused) _locked = true;
  }

  void _checkLock() {
    if (!_locked) return;
    _locked = false;
    final s = ref.read(userSettingsProvider).valueOrNull;
    if (s?.lockEnabled == true && s?.pinCode != null) {
      _showUnlockDialog(s!.pinCode!);
    }
  }

  void _showUnlockDialog(String correctPin) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('隐私锁'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请输入 PIN 码解锁'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (v) {
                  if (v.length == 4) {
                    if (v == correctPin) {
                      Navigator.pop(ctx);
                    } else {
                      ctrl.clear();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('PIN 码错误')));
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('退出应用'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
