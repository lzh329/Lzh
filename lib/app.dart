import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/migration/presentation/pages/database_sealed_page.dart';
import 'core/providers.dart';
import 'features/plan/domain/entities/plan_day_entity.dart';
import 'features/settings/domain/entities/user_settings_entity.dart';
import 'core/database/db_replaced_marker.dart';
import 'core/services/database_resolver.dart';
import 'core/services/notification_service.dart';
import 'core/services/auto_backup_service.dart';

class FitTrackApp extends ConsumerStatefulWidget {
  const FitTrackApp({super.key});

  @override
  ConsumerState<FitTrackApp> createState() => _FitTrackAppState();
}

class _FitTrackAppState extends ConsumerState<FitTrackApp>
    with WidgetsBindingObserver {
  /// 封存页详情（null = 未封存）
  String? _sealedDetail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动期读设置（提醒 / 主题）。
    //
    // 历史实现把这次读取放在 main.dart，在 runApp 之前 `await` 一个数据库查询
    // 且没有 try/catch —— 迁移一失败就白屏（降级页永远看不到），同时还多开了
    // 一个永不关闭的 AppDatabase 实例。现在统一在这里、走 databaseProvider 读，
    // 并且**读失败就用默认值把首帧渲染出来**，绝不阻塞启动。
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 恢复流程可能把库换掉，而用户没有杀进程就回到前台：
    // 这里消解一次（与 bootstrap 共用同一套单飞逻辑，连发两次只重建一次）。
    if (state == AppLifecycleState.resumed) _resolveIfReplaced();
  }

  Future<void> _resolveIfReplaced() async {
    if (!await DbReplacedMarker.exists()) return;
    final ok = await DatabaseResolver.resolveFromDocuments(
      closeCurrent: () async {
        try {
          await ref.read(databaseProvider).close();
        } catch (_) {}
      },
      reopen: () async {
        ref.invalidate(databaseProvider);
        // 触发一次真实查询：drift 会在这里重连（必要时重跑迁移）
        await ref.read(databaseProvider).customSelect('SELECT 1').get();
      },
    );
    if (!mounted) return;
    if (!ok) {
      // 保留标记，进封存页（下次 resume / 下次启动自然重试）
      setState(() => _sealedDetail = DatabaseSeal.message);
    } else {
      setState(() => _sealedDetail = null);
    }
  }

  Future<void> _bootstrap() async {
    UserSettingsEntity? settings;
    try {
      settings = await ref.read(userSettingsRepoProvider).get();
    } catch (_) {
      settings = null; // 读不到就用默认值启动，绝不让首帧挂掉
    }

    // 初始化提醒状态
    initReminderState(
      ref,
      enabled: settings?.reminderEnabled ?? false,
      hour: settings?.reminderHour ?? 8,
      minute: settings?.reminderMinute ?? 0,
    );
    // 初始化主题模式
    initThemeMode(ref, themeMode: settings?.themeMode);

    // 如果提醒已启用，排入通知
    if (settings?.reminderEnabled ?? false) {
      try {
        await _scheduleOnStart();
      } catch (_) {
        // 排通知失败不影响启动
      }
    }
    // 每周自动备份数据库（开关在「数据管理」页，默认开）
    _runAutoBackup();
  }

  Future<void> _runAutoBackup() async {
    try {
      final settings = await ref.read(userSettingsRepoProvider).get();
      await AutoBackupService.runIfNeeded(
        enabled: settings?.autoBackupEnabled ?? true,
      );
    } catch (_) {
      // 备份失败不影响启动
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
    if (_sealedDetail != null) {
      // 封存态：不可返回的全屏页，只给"退出"一条出路
      return DatabaseSealedPage(detail: _sealedDetail);
    }
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
