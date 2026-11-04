import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_records_page.dart';

import '../fake_database.dart';

/// 训练模块测试脚手架：真内存库 + 最小路由 + Provider 覆写。
///
/// 路由**故意按 `app_router.dart` 的声明顺序**写（`/workout/records` 在
/// `/workout/:id` 之前）—— 顺序写反的后果是"点训练记录进无效的训练ID"，
/// 这是本期最容易漏的一个 bug，测试用的路由必须和生产同序。
class WorkoutHarness {
  WorkoutHarness() : db = fakeDatabase();

  final AppDatabase db;

  GoRouter? _router;

  /// 当前路由位置（断言"点了之后到哪"用）。
  ///
  /// 取 `matches.last` 而不是 `uri`：`uri` 永远是**初始** URI，push 上去的
  /// 路由只会出现在 matches 里（踩过一次，记在这里）。
  String get location {
    final matches = _router?.routerDelegate.currentConfiguration.matches;
    if (matches == null || matches.isEmpty) return '';
    return matches.last.matchedLocation;
  }

  void dispose() => db.close();

  /// 造一条训练记录；返回 workout id
  Future<int> seedWorkout({
    required DateTime date,
    int? durationSec = 720,
    List<int> exerciseIds = const [1],
    int setsPerExercise = 2,
  }) async {
    final id = await db.into(db.workouts).insert(WorkoutsCompanion.insert(
          date: date,
          type: 'free',
          durationSec: Value(durationSec),
        ));
    for (final exerciseId in exerciseIds) {
      for (var i = 1; i <= setsPerExercise; i++) {
        await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
              workoutId: id,
              exerciseId: exerciseId,
              setNumber: i,
              reps: const Value(10),
              weightKg: const Value(20),
            ));
      }
    }
    return id;
  }

  /// 造一个动作库条目；返回 exercise id
  Future<int> seedExercise({String name = '深蹲', String category = 'strength'}) {
    return db.into(db.exercises).insert(ExercisesCompanion.insert(
          name: name,
          category: category,
        ));
  }

  /// 造一条称重记录（周条蓝点）
  Future<void> seedWeight(DateTime date, {double kg = 60}) async {
    await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
          date: date,
          weightKg: kg,
        ));
  }

  List<Override> overrides() => [
        databaseProvider.overrideWithValue(db),
        // 训练页的模板列表：给空列表，避免为它再灌种子数据
        workoutTemplatesProvider.overrideWith((ref) async => const []),
      ];

  Widget app({required String initialLocation}) {
    return ProviderScope(
      overrides: overrides(),
      child: MaterialApp.router(
        routerConfig: router(initialLocation: initialLocation),
      ),
    );
  }

  GoRouter router({required String initialLocation}) {
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/workout',
          builder: (_, __) => const QuickStartPage(),
        ),
        // 老深链 redirect（与 app_router.dart 同序、同语义，T-18）
        GoRoute(
          path: '/workout/quick-start',
          redirect: (_, __) => '/workout',
        ),
        // ⚠️ 必须在 :id 之前（与 app_router.dart 同序）
        GoRoute(
          path: '/workout/records',
          builder: (_, __) => const WorkoutRecordsPage(),
        ),
        GoRoute(
          path: '/workout/stats',
          builder: (_, __) => const _Stub(title: '训练统计页'),
        ),
        GoRoute(
          path: '/workout/active',
          builder: (_, __) => const _Stub(title: '训练中'),
        ),
        GoRoute(
          path: '/plan',
          builder: (_, __) => const _Stub(title: '训练计划页'),
        ),
        GoRoute(
          path: '/workout/:id',
          builder: (_, state) =>
              _Stub(title: '训练详情 ${state.pathParameters['id']}'),
        ),
        GoRoute(path: '/', builder: (_, __) => const _Stub(title: '首页')),
      ],
    );
    _router = router;
    return router;
  }
}

class _Stub extends StatelessWidget {
  const _Stub({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: Text(title)), body: Text(title));
  }
}
