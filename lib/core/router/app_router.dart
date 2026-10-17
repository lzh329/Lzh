import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_list_page.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_active_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_detail_page.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_metric_page.dart';
import 'package:fittrack/features/settings/presentation/pages/settings_page.dart';
import 'package:fittrack/features/exercise/presentation/pages/exercise_manage_page.dart';
import 'package:fittrack/features/goal/presentation/pages/goal_list_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_stats_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_list_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_create_page.dart';
import 'package:fittrack/features/plan/presentation/pages/plan_detail_page.dart';

import 'package:fittrack/features/settings/presentation/pages/body_info_page.dart';
import 'package:fittrack/features/settings/presentation/pages/voice_settings_page.dart';
import 'package:fittrack/features/diet/presentation/pages/diet_page.dart';
import 'package:fittrack/features/analysis/presentation/pages/weekly_report_page.dart';
import 'package:fittrack/features/analysis/presentation/pages/monthly_compare_page.dart';
import 'package:fittrack/features/water/presentation/water_page.dart';
import 'package:fittrack/features/trends/presentation/pages/trends_page.dart';
import 'package:fittrack/features/workout/presentation/pages/custom_workout_page.dart';

final navigatorKey = GlobalKey<NavigatorState>();

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
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNav(child: child),
      routes: [
        GoRoute(
          path: '/',
          pageBuilder: (context, state) => _tabPage(const DashboardPage(), state),
        ),
        GoRoute(
          path: '/workout',
          pageBuilder: (context, state) => _tabPage(const WorkoutListPage(), state),
        ),
        GoRoute(
          path: '/trends',
          pageBuilder: (context, state) => _tabPage(const TrendsPage(), state),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => _tabPage(const SettingsPage(), state),
        ),
      ],
    ),
    GoRoute(
      path: '/workout/quick-start',
      pageBuilder: (context, state) => _subPageTransition(const QuickStartPage(), state),
    ),
    GoRoute(
      path: '/workout/custom',
      pageBuilder: (context, state) => _subPageTransition(const CustomWorkoutPage(), state),
    ),
    GoRoute(
      path: '/workout/active',
      pageBuilder: (context, state) => _subPageTransition(const WorkoutActivePage(), state),
    ),
    GoRoute(
      path: '/workout/stats',
      pageBuilder: (context, state) => _subPageTransition(const WorkoutStatsPage(), state),
    ),
    GoRoute(
      path: '/workout/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        if (id == null) return _subPageTransition(const PlaceholderPage(title: '无效的训练ID'), state);
        return _subPageTransition(WorkoutDetailPage(workoutId: id), state);
      },
    ),
    GoRoute(
      path: '/plan/create',
      pageBuilder: (context, state) => _subPageTransition(const PlanCreatePage(), state),
    ),
    GoRoute(
      path: '/plan/:id',
      pageBuilder: (context, state) {
        final id = int.tryParse(state.pathParameters['id'] ?? '');
        if (id == null) return _subPageTransition(const PlaceholderPage(title: '无效的计划ID'), state);
        return _subPageTransition(PlanDetailPage(planId: id), state);
      },
    ),
    GoRoute(
      path: '/plan/:id/execute',
      pageBuilder: (context, state) => _subPageTransition(const WorkoutActivePage(), state),
    ),
    GoRoute(
      path: '/settings/exercises',
      pageBuilder: (context, state) => _subPageTransition(const ExerciseManagePage(), state),
    ),
    GoRoute(
      path: '/settings/body-info',
      pageBuilder: (context, state) => _subPageTransition(const BodyInfoPage(), state),
    ),
    GoRoute(
      path: '/settings/voice',
      pageBuilder: (context, state) => _subPageTransition(const VoiceSettingsPage(), state),
    ),
    GoRoute(
      path: '/plan',
      pageBuilder: (context, state) => _subPageTransition(const PlanListPage(), state),
    ),
    GoRoute(
      path: '/goals',
      pageBuilder: (context, state) => _subPageTransition(const GoalListPage(), state),
    ),
    GoRoute(
      path: '/analysis/weekly',
      pageBuilder: (context, state) => _subPageTransition(const WeeklyReportPage(), state),
    ),
    GoRoute(
      path: '/analysis/monthly',
      pageBuilder: (context, state) => _subPageTransition(const MonthlyComparePage(), state),
    ),
    GoRoute(
      path: '/water',
      pageBuilder: (context, state) => _subPageTransition(const WaterPage(), state),
    ),
    GoRoute(
      path: '/body',
      pageBuilder: (context, state) => _subPageTransition(const BodyMetricPage(), state),
    ),
    GoRoute(
      path: '/diet',
      pageBuilder: (context, state) => _subPageTransition(const DietPage(), state),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _subPageTransition(const SettingsPage(), state),
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
class ScaffoldWithNav extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNav({super.key, required this.child});

  int _currentIndex(String location) {
    if (location.startsWith('/workout')) return 1;
    if (location.startsWith('/trends')) return 2;
    if (location.startsWith('/profile')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final index = _currentIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          final routes = ['/', '/workout', '/trends', '/profile'];
          if (routes[i] != location) {
            context.go(routes[i]);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: '主控'),
          NavigationDestination(icon: Icon(Icons.fitness_center_outlined), selectedIcon: Icon(Icons.fitness_center), label: '训练'),
          NavigationDestination(icon: Icon(Icons.show_chart), selectedIcon: Icon(Icons.trending_up), label: '趋势'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
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
            Icon(Icons.construction, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text('即将上线', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
