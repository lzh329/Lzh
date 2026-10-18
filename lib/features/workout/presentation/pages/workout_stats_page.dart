import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

// ── Providers ──

final _statsPageDataProvider = FutureProvider<_StatsPageData>((ref) async {
  final workouts = await ref.watch(workoutRepoProvider).getAll();
  final bodyMetrics = await ref.watch(bodyMetricRepoProvider).getAll();
  return _StatsPageData(workouts: workouts, bodyMetrics: bodyMetrics);
});

final _prListProvider = FutureProvider<List<_PrExercise>>((ref) async {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.workoutSets).join([
    innerJoin(db.exercises, db.exercises.id.equalsExp(db.workoutSets.exerciseId)),
  ])
    ..where(db.workoutSets.isWarmup.equals(false) & db.workoutSets.reps.isNotNull());
  final rows = await query.get();
  final map = <int, _PrExercise>{};
  for (final row in rows) {
    final set = row.readTable(db.workoutSets);
    final ex = row.readTable(db.exercises);
    final entry = map.putIfAbsent(ex.id, () => _PrExercise(
      exerciseName: ex.name, bestWeight: 0, bestReps: 0, totalSets: 0, est1rm: 0,
    ));
    final w = set.weightKg ?? 0;
    final r = set.reps ?? 0;
    if (w > entry.bestWeight) entry.bestWeight = w;
    if (r > entry.bestReps) entry.bestReps = r;
    if (w > 0 && r > 0) {
      final e1rm = w * (1 + r / 30);
      if (e1rm > entry.est1rm) entry.est1rm = e1rm;
    }
    entry.totalSets++;
  }
  final result = map.values.toList();
  result.sort((a, b) => b.bestWeight.compareTo(a.bestWeight));
  return result;
});

// ── 页面 ──

const _green = Color(0xFFFF8A00);
const _amber = Color(0xFFFFC53D);

class WorkoutStatsPage extends ConsumerStatefulWidget {
  const WorkoutStatsPage({super.key});

  @override
  ConsumerState<WorkoutStatsPage> createState() => _WorkoutStatsPageState();
}

class _WorkoutStatsPageState extends ConsumerState<WorkoutStatsPage>
    with SingleTickerProviderStateMixin {
  late final _tabCtrl = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练统计'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '数据'),
            Tab(text: 'PR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildStatsTab(theme),
          _buildPrTab(theme),
        ],
      ),
    );
  }

  Widget _buildStatsTab(ThemeData theme) {
    return ref.watch(_statsPageDataProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e', style: TextStyle(color: theme.colorScheme.error))),
      data: (sdata) {
        final workouts = sdata.workouts;
        final bodyMetrics = sdata.bodyMetrics;

        if (workouts.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _green.withAlpha(26),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(Icons.bar_chart, size: 38, color: _green),
                ),
                const SizedBox(height: 16),
                Text('还没有训练数据', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('完成第一次训练后这里会有统计',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildStreakCard(theme, workouts),
            const SizedBox(height: 16),
            _buildWeeklyChart(theme, workouts),
            if (bodyMetrics.length >= 2) ...[
              const SizedBox(height: 16),
              _buildWeightTrendChart(theme, bodyMetrics),
            ],
            const SizedBox(height: 16),
            _buildCategoryPie(theme, workouts),
          ],
        );
      },
    );
  }

  Widget _buildPrTab(ThemeData theme) {
    return ref.watch(_prListProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
      data: (prs) {
        if (prs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _amber.withAlpha(26),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: const Icon(Icons.emoji_events,
                      size: 38, color: _amber),
                ),
                const SizedBox(height: 16),
                Text('还没有训练记录', style: theme.textTheme.titleMedium),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('完成训练后这里会显示你的最佳成绩',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: prs.length,
          itemBuilder: (context, index) {
            final p = prs[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.emoji_events,
                          size: 20,
                          color: index == 0 ? Colors.amber : theme.colorScheme.outline),
                        const SizedBox(width: 8),
                        Text(p.exerciseName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _PrStat(label: '最佳重量', value: p.bestWeight > 0 ? '${p.bestWeight.toStringAsFixed(1)} kg' : '—', theme: theme),
                        _PrStat(label: '最佳次数', value: p.bestReps > 0 ? '${p.bestReps} 次' : '—', theme: theme),
                        _PrStat(label: '估算 1RM', value: p.est1rm > 0 ? '${p.est1rm.toStringAsFixed(1)} kg' : '—', theme: theme),
                        _PrStat(label: '总组数', value: '${p.totalSets}', theme: theme),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── 原有统计卡片 ──

  Widget _buildStreakCard(ThemeData theme, List<WorkoutEntity> workouts) {
    final dates = workouts.map((w) => DateFormat('yyyyMMdd').format(w.date)).toSet().toList()..sort();
    int streak = 0;
    if (dates.isNotEmpty) {
      final today = DateFormat('yyyyMMdd').format(DateTime.now());
      final yesterday = DateFormat('yyyyMMdd').format(DateTime.now().subtract(const Duration(days: 1)));
      final lastDate = dates.last;
      if (lastDate == today || lastDate == yesterday) {
        streak = 1;
        for (int i = dates.length - 2; i >= 0; i--) {
          final prevDate = DateFormat('yyyyMMdd').parse(dates[i + 1]);
          final expected = DateFormat('yyyyMMdd').format(prevDate.subtract(const Duration(days: 1)));
          if (dates[i] == expected) { streak++; } else { break; }
        }
      }
    }
    final totalWorkouts = workouts.length;
    final totalSets = workouts.fold<int>(0, (sum, w) => sum + w.totalSets);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatItem(icon: Icons.local_fire_department, value: '$streak', label: '连续训练(天)', color: Colors.orange),
            _StatItem(icon: Icons.fitness_center, value: '$totalWorkouts', label: '总训练次数', color: theme.colorScheme.primary),
            _StatItem(icon: Icons.repeat, value: '$totalSets', label: '总完成组数', color: theme.colorScheme.tertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(ThemeData theme, List<WorkoutEntity> workouts) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final bars = <BarChartGroupData>[];
    for (int i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final dayWorkouts = workouts.where((w) =>
        w.date.year == day.year && w.date.month == day.month && w.date.day == day.day);
      final totalSets = dayWorkouts.fold<int>(0, (sum, w) => sum + w.totalSets);
      bars.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: totalSets.toDouble(), color: theme.colorScheme.primary, width: 16, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))]));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本周训练', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SizedBox(height: 160, child: BarChart(BarChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) => Text(['一','二','三','四','五','六','日'][v.toInt()], style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barGroups: bars,
            ))),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightTrendChart(ThemeData theme, List<BodyMetricEntity> metrics) {
    final spots = metrics.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.weightKg * 2)).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('体重趋势 (斤)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SizedBox(height: 160, child: LineChart(LineChartData(
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: (metrics.length / 4).ceilToDouble().clamp(1, 99), getTitlesWidget: (v, _) {
                  final idx = v.toInt().clamp(0, metrics.length - 1);
                  return Text(DateFormat('M/dd').format(metrics[idx].date), style: TextStyle(fontSize: 9, color: theme.colorScheme.outline));
                })),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: theme.colorScheme.primary, barWidth: 2.5, dotData: FlDotData(show: metrics.length <= 30), belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withAlpha(30)))],
            ))),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryPie(ThemeData theme, List<WorkoutEntity> workouts) {
    final catCount = <String, int>{};
    for (final w in workouts) {
      for (final s in w.sets) {
        catCount[s.exerciseId.toString()] = (catCount[s.exerciseId.toString()] ?? 0) + 1;
      }
    }
    if (catCount.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('组数分布', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            SizedBox(height: 150, child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pie_chart, size: 48, color: theme.colorScheme.outline),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('总组数: ${catCount.values.fold(0, (a, b) => a + b)}', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('每个动作的组数分布', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ],
            )),
          ],
        ),
      ),
    );
  }
}

// ── 数据模型 ──

class _StatsPageData {
  final List<WorkoutEntity> workouts;
  final List<BodyMetricEntity> bodyMetrics;
  const _StatsPageData({this.workouts = const [], this.bodyMetrics = const []});
}

class _PrExercise {
  final String exerciseName;
  double bestWeight;
  int bestReps;
  int totalSets;
  double est1rm;
  _PrExercise({required this.exerciseName, required this.bestWeight, required this.bestReps, required this.totalSets, required this.est1rm});
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _StatItem({required this.icon, required this.value, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color.withAlpha(200), size: 20),
        const SizedBox(height: 5),
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 10)),
      ],
    );
  }
}

class _PrStat extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  const _PrStat({required this.label, required this.value, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}
