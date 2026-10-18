import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/core/services/weight_analysis.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/calendar_widget.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/hero_weight_section.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/recent_workouts_section.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/stat_tiles_grid.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_timeline.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/weigh_in_fab.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

const _green = Color(0xFF66BB6A);
const _amber = Color(0xFFFFA726);
const _orange = Color(0xFFFF7043);
const _blue = Color(0xFF42A5F5);
const _purple = Color(0xFFAB47BC);

/// 主控页 —— v2 仪表盘
///
/// 结构：问候 + 连续打卡 → 大字体重区（进度条）→ 2×2 磁贴
/// → 今日动态时间线 → 最近训练 → 分析入口 → 训练日历
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

    // ── 今日动态 ──
    final entries = <TimelineEntry>[];
    if (data.todayMetric != null) {
      entries.add(TimelineEntry(
        title:
            '记录体重 ${(data.todayMetric!.weightKg * 2).toStringAsFixed(1)} 斤',
        subtitle: _fmtTime(data.todayMetric!.date),
        color: _amber,
      ));
    }
    for (final w in todayWorkouts) {
      final names = w.sets
          .map((s) => data.exerciseNames[s.exerciseId] ?? '')
          .where((n) => n.isNotEmpty)
          .toSet()
          .take(2)
          .join(' · ');
      entries.add(TimelineEntry(
        title: names.isEmpty ? '完成训练' : '完成训练 · $names',
        subtitle: _fmtTime(w.date),
        color: _green,
      ));
    }
    if (data.todayCalories != null) {
      entries.add(TimelineEntry(
        title: '记录饮食 ${data.todayCalories!.round()} kcal',
        color: _orange,
      ));
    } else {
      entries.add(const TimelineEntry(title: '待记录：今日饮食', done: false));
    }

    // ── 2×2 磁贴 ──
    final tiles = [
      StatTileData(
        icon: Icons.local_fire_department,
        color: _orange,
        label: '今日热量',
        value:
            data.todayCalories != null ? '${data.todayCalories!.round()}' : '—',
        unit: 'kcal',
        onTap: () => context.push('/diet'),
      ),
      StatTileData(
        icon: Icons.water_drop,
        color: _blue,
        label: '今日饮水',
        value: '${data.todayCups}',
        unit: '/ 8 杯',
        onTap: () => context.push('/water'),
      ),
      StatTileData(
        icon: Icons.fitness_center,
        color: _green,
        label: '今日训练',
        value: '${todayWorkouts.length}',
        unit: '次',
        onTap: () => context.push('/workout/quick-start'),
      ),
      StatTileData(
        icon: Icons.calendar_month,
        color: _purple,
        label: '本周训练',
        value: '${data.weekWorkoutDays}',
        unit: '/ 7 天',
        onTap: () => context.push('/analysis/weekly'),
      ),
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          GreetingHeader(
            streakDays: streak,
            avatarAsset: guga.stage.asset,
            gugaName: guga.stage.name,
            upgradeHint: guga.isMax
                ? null
                : '距升级 ${guga.remainToNext!.toStringAsFixed(1)} 斤',
          ),
          const SizedBox(height: 22),
          HeroWeightSection(
            currentJin: currentJin,
            targetJin: targetJin,
            progress: progress,
            weekChangeJin: weekChange,
            daysToTarget: daysToTarget,
            onTap: () => context.push('/body'),
          ),
          const SizedBox(height: 24),
          StatTilesGrid(tiles: tiles),
          const SizedBox(height: 22),
          TodayTimeline(entries: entries),
          const SizedBox(height: 22),
          RecentWorkoutsSection(
            workouts: data.recentWorkouts,
            exerciseNames: data.exerciseNames,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _MiniLink(
                  icon: Icons.summarize_outlined,
                  label: '本周周报',
                  onTap: () => context.push('/analysis/weekly'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniLink(
                  icon: Icons.calendar_view_month,
                  label: '月度对比',
                  onTap: () => context.push('/analysis/monthly'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('训练日历', style: theme.textTheme.titleSmall),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
              child: CalendarWidget(
                workoutDates: data.calendarWorkoutDates,
                weighInDates: data.weighInDates,
                onDayTap: (date) => _showDayDetail(
                  context,
                  date,
                  data.allWorkouts,
                  data.exerciseNames,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 点击日历某天：底部弹层展示当天训练
  void _showDayDetail(
    BuildContext context,
    DateTime date,
    List<WorkoutEntity> allWorkouts,
    Map<int, String> exerciseNames,
  ) {
    final dayWorkouts =
        allWorkouts.where((w) => _sameDay(w.date, date)).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(date),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (dayWorkouts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '当天没有训练记录',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                )
              else
                ...dayWorkouts.map((w) {
                  final names = w.sets
                      .map((s) => exerciseNames[s.exerciseId] ?? '')
                      .where((n) => n.isNotEmpty)
                      .toSet()
                      .join(' · ');
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.fitness_center,
                        size: 18, color: _green),
                    title: Text(names.isEmpty ? '训练' : names,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${w.sets.length} 组'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/workout/${w.id}');
                    },
                  );
                }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _MiniLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniLink({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withAlpha(24)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }
}

// ───────────── 辅助函数 ─────────────

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _fmtTime(DateTime d) => DateFormat('HH:mm').format(d);

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
