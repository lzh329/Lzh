import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_log_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_records_page.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_active_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_detail_page.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_metric_page.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_album_page.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_compare_page.dart';
import 'package:fittrack/features/settings/presentation/pages/character_page.dart';
import 'package:fittrack/features/settings/presentation/pages/settings_page.dart';
import 'package:fittrack/features/exercise/presentation/pages/exercise_manage_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_stats_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_list_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_create_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_detail_page.dart';

import 'package:fittrack/features/settings/presentation/pages/profile_page.dart';
import 'package:fittrack/features/settings/presentation/pages/data_management_page.dart';
import 'package:fittrack/features/settings/presentation/pages/voice_settings_page.dart';
import 'package:fittrack/features/ai/presentation/pages/ai_chat_page.dart';
import 'package:fittrack/features/ai/presentation/pages/ai_coach_settings_page.dart';
import 'package:fittrack/features/ai/presentation/pages/ai_persona_page.dart';
import 'package:fittrack/features/ai/presentation/pages/coach_memory_page.dart';
import 'package:fittrack/features/diet/presentation/pages/diet_page.dart';
import 'package:fittrack/features/analysis/presentation/pages/weekly_report_page.dart';
import 'package:fittrack/features/analysis/presentation/pages/monthly_compare_page.dart';
import 'package:fittrack/features/water/presentation/water_page.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/trends/presentation/pages/trends_page.dart';
import 'package:fittrack/features/workout/presentation/pages/custom_workout_page.dart';
import 'package:fittrack/features/workout/presentation/pages/template_edit_page.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

final navigatorKey = GlobalKey<NavigatorState>();

/// 页面可见性观察者。
///
/// 首页「从教练页返回时自动播一次动作」需要知道"我又回到前台了" ——
/// 这不是 app 生命周期（App 一直在前台），而是**路由栈变化**，
/// 只有 RouteObserver 能观察到（`didPopNext`）。
final appRouteObserver = RouteObserver<PageRoute<dynamic>>();

/// 统一的子页面过渡（底部滑入 + 淡入）
Page<void> _subPageTransition(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 250),
  );
}

final appRouter = GoRouter(
  navigatorKey: navigatorKey,
  observers: [appRouteObserver],
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNav(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              _tabPage(const DashboardPage(), state),
        ),
        GoRoute(
          path: '/workout',
          pageBuilder: (context, state) =>
              _tabPage(const QuickStartPage(), state),
        ),
        GoRoute(
          path: '/trends',
          pageBuilder: (context, state) => _tabPage(const TrendsPage(), state),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              _tabPage(const SettingsPage(), state),
        ),
      ],
    ),
    // 老路径保留并 redirect → /workout：首页「今日任务」、通知、AI 工具回执里
    // 都可能还带着 /workout/quick-start，直接删会断链（用户点进去白屏）。
    // 与 /settings/body-info、/goals 同惯例。
    GoRoute(
      path: '/workout/quick-start',
      redirect: (_, __) => '/workout',
    ),
    // ⚠️ `/workout/records` 必须声明在 `/workout/:id` 之前：
    //    go_router 按声明顺序匹配，写反了就会把 "records" 当成训练 id 解析 →
    //    点「训练记录」进「无效的训练ID」。下面 stats / active / template-edit
    //    都排在 :id 前面，新路由照此位置插入。
    GoRoute(
      path: '/workout/records',
      pageBuilder: (context, state) =>
          _subPageTransition(const WorkoutRecordsPage(), state),
    ),
    // 「记一笔」：先选模板 → 带出动作 → 填实际组次重 → 保存
    GoRoute(
      path: '/workout/log/new',
      pageBuilder: (context, state) =>
          _subPageTransition(const WorkoutLogPage(), state),
    ),
    GoRoute(
      path: '/workout/custom',
      pageBuilder: (context, state) =>
          _subPageTransition(const CustomWorkoutPage(), state),
    ),
    GoRoute(
      path: '/workout/template-edit',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.uri.queryParameters['id'] ?? '');
        return _subPageTransition(TemplateEditPage(templateId: id), state);
      },
    ),
    GoRoute(
      path: '/workout/active',
      pageBuilder: (context, state) {
        final extra = state.extra;
        return _subPageTransition(
          WorkoutActivePage(
            initialSlots: extra is List<ExerciseSlot> ? extra : null,
          ),
          state,
        );
      },
    ),
    GoRoute(
      path: '/workout/stats',
      pageBuilder: (context, state) =>
          _subPageTransition(const WorkoutStatsPage(), state),
    ),
    // 芯片「去开练」（无计划）的目标：顶层路由，push 能返回对话。
    // 不能用底部 Tab /workout —— 从聊天这种顶层路由 push 一个 Shell 子路由
    // 在真机上会白屏（本地空库测试复现不出）。
    GoRoute(
      path: '/workout/start',
      pageBuilder: (context, state) =>
          _subPageTransition(const QuickStartPage(), state),
    ),
    // 芯片「看趋势」的目标：同上去壳化，push 能返回对话
    GoRoute(
      path: '/trends/view',
      pageBuilder: (context, state) =>
          _subPageTransition(const TrendsPage(), state),
    ),
    GoRoute(
      path: '/workout/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        if (id == null) {
          return _subPageTransition(
              const PlaceholderPage(title: '无效的训练ID'), state);
        }
        return _subPageTransition(WorkoutDetailPage(workoutId: id), state);
      },
    ),
    GoRoute(
      path: '/plan/create',
      pageBuilder: (context, state) =>
          _subPageTransition(const PlanCreatePage(), state),
    ),
    GoRoute(
      path: '/plan/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        if (id == null) {
          return _subPageTransition(
              const PlaceholderPage(title: '无效的计划ID'), state);
        }
        return _subPageTransition(PlanDetailPage(planId: id), state);
      },
    ),
    GoRoute(
      path: '/plan/:id/execute',
      pageBuilder: (context, state) =>
          _subPageTransition(const WorkoutActivePage(), state),
    ),
    GoRoute(
      path: '/settings/exercises',
      pageBuilder: (context, state) =>
          _subPageTransition(const ExerciseManagePage(), state),
    ),
    GoRoute(
      path: '/settings/profile',
      pageBuilder: (context, state) =>
          _subPageTransition(const ProfilePage(), state),
    ),
    // 「我的形象」：入口在「我的 → 我的档案」，语义是身份类设置，
    // 和「个人档案」「身体相册」同一层。**不放教练设定下面** ——
    // 那条路是「点角色 → 进聊天 → 右上角设置 → 往下滚」，3 层且语义错位。
    GoRoute(
      path: '/settings/character',
      pageBuilder: (context, state) =>
          _subPageTransition(const CharacterPage(), state),
    ),
    // 老入口保留并重定向：别处（AI 建议文案、旧通知等）可能还在跳这个路径，
    // 直接删会断链，用户点进去是白屏
    GoRoute(
      path: '/settings/body-info',
      redirect: (_, __) => '/settings/profile',
    ),
    // 「目标管理」入口已下线（体重目标并入个人档案的「身体信息」）。
    // 保留老路径重定向，避免旧通知 / 历史深链点进来白屏。
    GoRoute(
      path: '/goals',
      redirect: (_, __) => '/settings/profile',
    ),

    GoRoute(
      path: '/settings/voice',
      pageBuilder: (context, state) =>
          _subPageTransition(const VoiceSettingsPage(), state),
    ),
    GoRoute(
      path: '/ai/coach',
      pageBuilder: (context, state) {
        // extra 支持两种：纯文本（预填问题）或 {imagePath, text}
        final extra = state.extra;
        String? imagePath;
        String? text;
        if (extra is String) {
          text = extra;
        } else if (extra is Map) {
          imagePath = extra['imagePath'] as String?;
          text = extra['text'] as String?;
        }
        return _subPageTransition(
          AiChatPage(initialImagePath: imagePath, initialText: text),
          state,
        );
      },
    ),
    GoRoute(
      path: '/ai/settings',
      pageBuilder: (context, state) =>
          _subPageTransition(const AiCoachSettingsPage(), state),
    ),
    GoRoute(
      path: '/ai/memory',
      pageBuilder: (context, state) =>
          _subPageTransition(const CoachMemoryPage(), state),
    ),
    GoRoute(
      path: '/ai/persona',
      pageBuilder: (context, state) =>
          _subPageTransition(const AiPersonaPage(), state),
    ),
    GoRoute(
      path: '/settings/data',
      pageBuilder: (context, state) =>
          _subPageTransition(const DataManagementPage(), state),
    ),
    GoRoute(
      path: '/plan',
      pageBuilder: (context, state) =>
          _subPageTransition(const PlanListPage(), state),
    ),

    GoRoute(
      path: '/analysis/weekly',
      pageBuilder: (context, state) =>
          _subPageTransition(const WeeklyReportPage(), state),
    ),
    GoRoute(
      path: '/analysis/monthly',
      pageBuilder: (context, state) =>
          _subPageTransition(const MonthlyComparePage(), state),
    ),
    GoRoute(
      path: '/water',
      pageBuilder: (context, state) =>
          _subPageTransition(const WaterPage(), state),
    ),
    GoRoute(
      path: '/body',
      pageBuilder: (context, state) =>
          _subPageTransition(const BodyMetricPage(), state),
    ),
    GoRoute(
      path: '/body/compare',
      pageBuilder: (context, state) =>
          _subPageTransition(const BodyComparePage(), state),
    ),
    GoRoute(
      path: '/body/album',
      pageBuilder: (context, state) =>
          _subPageTransition(const BodyAlbumPage(), state),
    ),
    GoRoute(
      path: '/diet',
      pageBuilder: (context, state) =>
          _subPageTransition(const DietPage(), state),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) =>
          _subPageTransition(const SettingsPage(), state),
    ),
  ],
);

/// Tab 切换淡入淡出过渡
Page<void> _tabPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.5, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOut),
        ),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 180),
  );
}

/// 带底部导航的壳
///
/// 只在四个一级 Tab（主控/训练/趋势/我的）出现；子页是壳外的独立路由，
/// 返回键在子页上是正常 pop，回到壳之后才走下面的"双击退出"。
class ScaffoldWithNav extends StatefulWidget {
  final Widget child;
  const ScaffoldWithNav({super.key, required this.child});

  @override
  State<ScaffoldWithNav> createState() => _ScaffoldWithNavState();
}

class _ScaffoldWithNavState extends State<ScaffoldWithNav> {
  /// 上次按返回键的时刻；2 秒内再按一次才真正退出
  DateTime? _lastBack;

  static const _doublePressWindow = Duration(seconds: 2);

  int _currentIndex(String location) {
    if (location.startsWith('/workout')) return 1;
    if (location.startsWith('/trends')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  void _onBackPressed() {
    final now = DateTime.now();
    if (_lastBack == null || now.difference(_lastBack!) > _doublePressWindow) {
      _lastBack = now;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('再按一次退出应用'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    // 2 秒内第二次按返回 → 真正退出
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _currentIndex(location);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // didPop == true 说明这次返回被允许了（不会发生，因为 canPop=false）；
        // 我们只处理"系统尝试返回但被拦下"的分支。
        if (didPop) return;
        _onBackPressed();
      },
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          final routes = ['/', '/workout', '/trends', '/profile'];
          if (routes[i] != location) {
            context.go(routes[i]);
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: '主控'),
          NavigationDestination(
              icon: Icon(Icons.fitness_center_outlined),
              selectedIcon: Icon(Icons.fitness_center),
              label: '训练'),
          NavigationDestination(
              icon: Icon(Icons.show_chart),
              selectedIcon: Icon(Icons.trending_up),
              label: '趋势'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的'),
          ],
        ),
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction,
                size: 64, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text('即将上线', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
