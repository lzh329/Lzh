import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/migration/presentation/pages/database_sealed_page.dart';
import 'features/settings/presentation/pages/lock_screen.dart';
import 'core/providers.dart';
import 'features/settings/domain/entities/user_settings_entity.dart';
import 'core/database/db_replaced_marker.dart';
import 'core/services/database_resolver.dart';
import 'core/services/reminder_scheduler.dart';
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

  /// 上次重排提醒时的自然日（T03-D5 跨天恢复用）
  DateTime? _scheduledDay;

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
    if (state == AppLifecycleState.resumed) {
      _resolveIfReplaced();
      _rescheduleIfDayChanged();
    }
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

  /// 启动时排一次提醒。
  ///
  /// 今天生病（`reminderPaused`）时今天那条不排，其余星期几照排 —— 判定在
  /// [ReminderScheduler] 里，这里只负责把活跃计划喂进去。
  Future<void> _scheduleOnStart() async {
    final plans = await ref.read(planRepoProvider).getAll();

    await ref.read(reminderSchedulerProvider).reschedule(
          enabled: true,
          hour: ref.read(reminderHourProvider),
          minute: ref.read(reminderMinuteProvider),
          workoutSlots: buildWorkoutSlots(plans),
          weighInId: kWeighInReminderId,
        );
    _scheduledDay = _dayOf(DateTime.now());
  }

  /// 跨天自动恢复（T03-D5）：自然日一变就重排，昨天被跳过的那条自己回来。
  ///
  /// 没有后台定时器，靠的是用户回到 App 的这一刻补排一次 —— 这也正是
  /// 「仅今天有效，明天自动恢复」这句文案的实现方式。
  Future<void> _rescheduleIfDayChanged() async {
    if (!ref.read(reminderEnabledProvider)) return;
    if (_scheduledDay == _dayOf(DateTime.now())) return;
    try {
      await _scheduleOnStart();
    } catch (_) {
      // 重排失败不影响使用，下次 resume 会再试
    }
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    initializeDateFormatting('zh_CN');
    if (_sealedDetail != null) {
      // 封存态：不可返回的全屏页，只给"退出"一条出路
      return DatabaseSealedPage(detail: _sealedDetail);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
        // 锁屏必须挂在 MaterialApp **内部**（builder 里）。
        // 挂在外面时它拿不到 Directionality / MediaQuery / Material 本地化，
        // Scaffold 根本画不出来，但那一层 Positioned.fill 照样吞掉全部点击——
        // 用户看到的就是「主页好好的，点什么都没反应」（2026-10-29 真实事故）。
        builder: (context, child) => _LockGate(
          child: child ?? const SizedBox.shrink(),
        ),
        routerConfig: appRouter,
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
  /// 初始就按**锁着**处理：异步读设置之前谁也不知道该不该锁，
  /// 这时唯一的正确姿势是"宁可多锁一秒，也不泄露一秒"。
  /// （原实现初始 false → 冷启动不锁，只有切后台回来才校验，等于锁只在
  ///  App 已经在运行的情况下才生效。）
  bool _locked = true;

  /// 已确认可以解锁的 PIN；null = 还没读到设置
  String? _correctPin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLockState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 冷启动时读设置，决定是否需要锁
  Future<void> _loadLockState() async {
    UserSettingsEntity? s;
    try {
      s = await ref.read(userSettingsProvider.future);
    } catch (_) {
      s = null;
    }
    if (!mounted) return;
    final pin = s?.pinCode;
    final needLock = shouldLockOnColdStart(
      lockEnabled: s?.lockEnabled == true,
      pinCode: pin,
    );
    setState(() {
      _correctPin = needLock ? pin : null;
      _locked = needLock;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 进后台立刻遮住（用 setState 才能让遮罩立刻生效，而不是等回来才画）
    if (state == AppLifecycleState.paused && _correctPin != null) {
      setState(() => _locked = true);
    }
  }

  /// 「忘记 PIN」的唯一出路：清掉锁（**只动锁，不动任何业务数据**）。
  ///
  /// 单人自用、本地无云，忘了 PIN 就等于永久失去 App —— 比防盗更值得防。
  Future<void> _forgotPin() async {
    try {
      await ref.read(userSettingsRepoProvider).clearLock();
      ref.invalidate(userSettingsProvider);
    } catch (e) {
      debugPrint('清除隐私锁失败: $e');
    }
    if (!mounted) return;
    setState(() {
      _correctPin = null;
      _locked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pin = _correctPin;
    return Stack(
      children: [
        // ⚠️ 用**叠层**而不是替换 child：替换会把路由栈销毁，
        // 解锁后用户被扔回首页、丢掉原来的上下文。
        widget.child,
        if (_locked && pin != null)
          Positioned.fill(
            child: LockScreen(
              correctPin: pin,
              onUnlocked: () => setState(() => _locked = false),
              onForgotPin: _forgotPin,
            ),
          ),
      ],
    );
  }
}
