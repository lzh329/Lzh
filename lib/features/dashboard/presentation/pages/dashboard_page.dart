import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/core/services/weight_analysis.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/hero_weight_section.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/recent_workouts_section.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_tasks_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/weight_spark_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/weigh_in_fab.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 主控页 —— v2 仪表盘（每日任务 + 咕嘎陪伴融合版）
///
/// 结构：问候 → 今日任务卡（3 件事）→ 大字体重区（进度条）→ 今日数据三格
///      → 体重趋势 → 最近训练 → 页脚入口
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);
    final settings = ref.watch(userSettingsProvider).valueOrNull;

    return Scaffold(
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(dashboardDataProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (data) => _DashboardBody(data: data, settings: settings),
      ),
      floatingActionButton: const WeighInFab(),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final DashboardData data;
  final UserSettingsEntity? settings;

  const _DashboardBody({required this.data, required this.settings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = data.latestMetric;
    final today = DateTime.now();

    // ── 派生数据 ──
    final currentJin = latest != null ? latest.weightKg * 2 : null;
    final targetJin = settings?.targetWeightKg != null
        ? settings!.targetWeightKg! * 2
        : null;
    final startJin =
        data.firstMetric != null ? data.firstMetric!.weightKg * 2 : null;
    final daysToTarget = WeightAnalysis.predictDaysToTarget(
        data.allMetrics, settings?.targetWeightKg);
    final weekChange = (data.weekStartMetric != null &&
            latest != null &&
            data.weekStartMetric!.id != latest.id)
        ? currentJin! - data.weekStartMetric!.weightKg * 2
        : null;
    final progress = WeightAnalysis.targetProgress(
      startJin: startJin,
      currentJin: currentJin,
      targetJin: targetJin,
    );

    // 连续打卡（体重或训练任一有记录算一天）
    final streak = _calcStreak([
      ...data.allMetrics.map((m) => m.date),
      ...data.allWorkouts.map((w) => w.date),
    ]);

    // 咕嘎形态（首页陪伴头像 + 距升级提示）
    final totalLossJin =
        (startJin != null && currentJin != null) ? startJin - currentJin : 0.0;
    final guga = GugaLevelService.resolve(totalLossJin);

    final todayWorkouts =
        data.allWorkouts.where((w) => _sameDay(w.date, today)).toList();

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          // 1) 问候 + 连续打卡 + 咕嘎头像
          GreetingHeader(
            streakDays: streak,
            avatarAsset: guga.stage.asset,
            gugaName: guga.stage.name,
            upgradeHint: guga.isMax
                ? null
                : '距升级 ${guga.remainToNext!.toStringAsFixed(1)} 斤',
          ),
          const SizedBox(height: 20),

          // 2) 今日任务：记录体重 / 完成训练 / 记录饮食 + 咕嘎鼓励
          TodayTasksCard(
            todayWeightJin: data.todayMetric != null
                ? data.todayMetric!.weightKg * 2
                : null,
            workoutCount: todayWorkouts.length,
            calories: data.todayCalories,
            gugaAsset: guga.stage.asset,
            // 首页的记录体重入口由 WeighInFab 内部弹层承载，未对外暴露回调，
            // 因此该行未完成时不展示「去记录」按钮（仅保留勾选框）。
            onTapWeight: null,
            onTapWorkout: () => context.push('/workout/quick-start'),
            onTapDiet: () => context.push('/diet'),
          ),
          const SizedBox(height: 22),

          // 3) 大字体重 + 本周变化 + 目标进度
          HeroWeightSection(
            currentJin: currentJin,
            targetJin: targetJin,
            progress: progress,
            weekChangeJin: weekChange,
            daysToTarget: daysToTarget,
            onTap: () => context.push('/body'),
          ),
          const SizedBox(height: 24),

          // 4) 今日数据三格
          _TodayStatsCard(
            calories: data.todayCalories,
            cups: data.todayCups,
            workoutCount: todayWorkouts.length,
            onCaloriesTap: () => context.push('/diet'),
            onWaterTap: () => context.push('/water'),
            onWorkoutTap: () => context.push('/workout/quick-start'),
          ),
          const SizedBox(height: 22),

          // 5) 体重趋势（近 7 次）
          WeightSparkCard(
            metrics: data.allMetrics,
            onTap: () => context.push('/body'),
          ),
          const SizedBox(height: 22),

          // 6) 最近训练
          RecentWorkoutsSection(
            workouts: data.recentWorkouts,
            exerciseNames: data.exerciseNames,
          ),
          const SizedBox(height: 8),

          // 页脚：分析入口
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FooterLink(
                label: '本周周报',
                onTap: () => context.push('/analysis/weekly'),
              ),
              Text(
                ' · ',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
              _FooterLink(
                label: '月度对比',
                onTap: () => context.push('/analysis/monthly'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 今日数据：一张卡内三等分（热量 / 饮水 / 训练）
class _TodayStatsCard extends StatelessWidget {
  final double? calories;
  final int cups;
  final int workoutCount;
  final VoidCallback onCaloriesTap;
  final VoidCallback onWaterTap;
  final VoidCallback onWorkoutTap;

  const _TodayStatsCard({
    required this.calories,
    required this.cups,
    required this.workoutCount,
    required this.onCaloriesTap,
    required this.onWaterTap,
    required this.onWorkoutTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: _TodayStatCell(
                label: '今日热量',
                value: calories != null ? '${calories!.round()}' : '—',
                unit: 'kcal',
                onTap: onCaloriesTap,
              ),
            ),
            const _CellDivider(),
            Expanded(
              child: _TodayStatCell(
                label: '今日饮水',
                value: '$cups',
                unit: '杯',
                onTap: onWaterTap,
              ),
            ),
            const _CellDivider(),
            Expanded(
              child: _TodayStatCell(
                label: '今日训练',
                value: '$workoutCount',
                unit: '次',
                onTap: onWorkoutTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三格之间的细分隔线
class _CellDivider extends StatelessWidget {
  const _CellDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: Colors.white.withAlpha(14),
    );
  }
}

class _TodayStatCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final VoidCallback onTap;

  const _TodayStatCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              unit,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontSize: 10, color: outline),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 页脚文字链
class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
        ),
      ),
    );
  }
}

// ───────────── 辅助函数 ─────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 连续打卡天数：从今天（或昨天）向前连续有记录的天数
int _calcStreak(List<DateTime> dates) {
  if (dates.isEmpty) return 0;
  final set = dates.map((d) => DateTime(d.year, d.month, d.day)).toSet();
  final now = DateTime.now();
  var day = DateTime(now.year, now.month, now.day);
  if (!set.contains(day)) {
    day = day.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (set.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}
