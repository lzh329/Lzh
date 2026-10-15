import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

class WeeklyReportPage extends ConsumerWidget {
  const WeeklyReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyRepo = ref.watch(bodyMetricRepoProvider);
    final workoutRepo = ref.watch(workoutRepoProvider);
    final dietRepo = ref.watch(dietRepoProvider);
    final userSettingsAsync = ref.watch(userSettingsProvider);
    final theme = Theme.of(context);

    final now = DateTime.now();
    // 本周一至周日
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));

    return Scaffold(
      appBar: AppBar(
        title: Text('${DateFormat('M月d日').format(monday)} - ${DateFormat('M月d日').format(sunday)} 周报'),
      ),
      body: FutureBuilder<_WeeklyReportData>(
        future: _loadData(bodyRepo, workoutRepo, dietRepo, monday, sunday),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _WeeklyReportData();
          final us = userSettingsAsync.valueOrNull;

          if (data.weekMetrics.isEmpty && data.weekWorkouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_graph, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('本周还没有数据', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 4),
                  Text('记录体重和训练后，周报自动生成', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── 体重变化 ──
              if (data.weekMetrics.length >= 2) ...[
                _SectionTitle(icon: Icons.monitor_weight, title: '体重'),
                const SizedBox(height: 8),
                _buildWeightCard(theme, data, us),
                const SizedBox(height: 20),
              ],

              // ── 训练 ──
              _SectionTitle(icon: Icons.fitness_center, title: '训练'),
              const SizedBox(height: 8),
              _buildTrainingCard(theme, data),
              const SizedBox(height: 20),

              // ── 训练-体重关联 ──
              if (data.weekWorkouts.isNotEmpty && data.weekMetrics.isNotEmpty) ...[
                _SectionTitle(icon: Icons.insights, title: '训练-体重关联'),
                const SizedBox(height: 8),
                _buildCorrelationChart(theme, data),
                const SizedBox(height: 20),
              ],

              // ── 饮食 ──
              _SectionTitle(icon: Icons.restaurant, title: '饮食'),
              const SizedBox(height: 8),
              _buildDietCard(theme, data, us),
            ],
          );
        },
      ),
    );
  }

  Future<_WeeklyReportData> _loadData(repos, workoutRepo, dietRepo, monday, sunday) async {
    final weekMetrics = await repos.getAll(from: monday, to: sunday);
    final weekWorkouts = await workoutRepo.getAll(from: monday, to: sunday);

    // 本周每日热量
    final dailyCals = <DateTime, double>{};
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(DateTime.now())) break;
      dailyCals[DateTime(day.year, day.month, day.day)] = await dietRepo.getDailyCalories(day);
    }

    return _WeeklyReportData(
      weekMetrics: weekMetrics,
      weekWorkouts: weekWorkouts,
      dailyCalories: dailyCals,
    );
  }

  Widget _buildWeightCard(ThemeData theme, _WeeklyReportData data, UserSettingsEntity? us) {
    final first = data.weekMetrics.first;
    final last = data.weekMetrics.last;
    final delta = (last.weightKg - first.weightKg) * 2;
    final isDown = delta < -0.05;
    final isUp = delta > 0.05;
    final arrow = isDown ? '↓' : isUp ? '↑' : '→';
    final deltaColor = isDown ? Colors.green : isUp ? Colors.red : theme.colorScheme.outline;

    // 减脂速度
    final daysDiff = last.date.difference(first.date).inDays.clamp(1, 7);
    final weeklyRate = (delta / daysDiff * 7);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReportStat(label: '周初', value: '${(first.weightKg * 2).toStringAsFixed(1)} 斤', theme: theme),
                Icon(Icons.arrow_forward, color: deltaColor, size: 20),
                _ReportStat(label: '周末', value: '${(last.weightKg * 2).toStringAsFixed(1)} 斤', theme: theme),
                const SizedBox(width: 8),
                _ReportStat(
                  label: '变化',
                  value: '$arrow ${delta.abs().toStringAsFixed(1)} 斤',
                  color: deltaColor,
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('减脂速度: ${weeklyRate.abs().toStringAsFixed(1)} 斤/周',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                if (weeklyRate.abs() >= 0.5 && weeklyRate.abs() <= 2.0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withAlpha(25), borderRadius: BorderRadius.circular(4)),
                    child: const Text('✓ 健康区间', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            if (us?.targetWeightKg != null) ...[
              const SizedBox(height: 8),
              Text('距目标 ${(us!.targetWeightKg! * 2).toStringAsFixed(1)} 斤 · 还差 ${((last.weightKg - us.targetWeightKg!) * 2).toStringAsFixed(1)} 斤',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrainingCard(ThemeData theme, _WeeklyReportData data) {
    final workoutDays = data.weekWorkouts
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet();
    final totalSets = data.weekWorkouts.fold<int>(0, (sum, w) => sum + w.totalSets);
    final totalDurationMin = data.weekWorkouts.fold<int>(0, (sum, w) => sum + (w.durationSec ?? 0)) ~/ 60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReportStat(label: '训练天数', value: '${workoutDays.length} / 7 天', theme: theme),
                _ReportStat(label: '完成组数', value: '$totalSets 组', theme: theme),
                if (totalDurationMin > 0)
                  _ReportStat(label: '训练时长', value: '$totalDurationMin 分钟', theme: theme),
              ],
            ),
            if (data.weekWorkouts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('本周没有训练记录', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorrelationChart(ThemeData theme, _WeeklyReportData data) {
    final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    // 构建每日映射
    final weightByDay = <int, double>{};
    for (final m in data.weekMetrics) {
      final dayIdx = m.date.difference(monday).inDays;
      if (dayIdx >= 0 && dayIdx < 7) weightByDay[dayIdx] = m.weightKg;
    }
    final workoutDays = data.weekWorkouts
        .map((w) => w.date.difference(monday).inDays)
        .where((d) => d >= 0 && d < 7)
        .toSet();

    if (weightByDay.length < 2 && workoutDays.isEmpty) return const SizedBox.shrink();

    // 体重范围（用于归一化显示）
    final weights = weightByDay.values.toList();
    final minW = weights.isEmpty ? 0 : weights.reduce((a, b) => a < b ? a : b);
    final maxW = weights.isEmpty ? 1 : weights.reduce((a, b) => a > b ? a : b);
    final wRange = (maxW - minW).abs() < 0.1 ? 1.0 : maxW - minW;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('体重', style: theme.textTheme.bodySmall?.copyWith(color: Colors.blue)),
                const SizedBox(width: 16),
                Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: theme.colorScheme.primary, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('训练日', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                const Spacer(),
                Text('${minW.toStringAsFixed(1)} - ${maxW.toStringAsFixed(1)} kg',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(7, (i) {
                  final hasWeight = weightByDay.containsKey(i);
                  final hasWorkout = workoutDays.contains(i);
                  final w = weightByDay[i];
                  final normalized = hasWeight ? ((w! - minW) / wRange).clamp(0.0, 1.0) : 0.0;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: i < 6 ? 3 : 0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // 体重点（上方）
                          if (hasWeight)
                            Container(
                              height: (normalized * 60).clamp(4.0, 60.0),
                              width: 6,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          const Spacer(),
                          // 训练指示
                          if (hasWorkout)
                            Container(
                              width: double.infinity,
                              height: 4,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          const SizedBox(height: 6),
                          Text(dayLabels[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DateTime.now().weekday == (i + 1) % 7 + 1
                                  ? theme.colorScheme.primary : theme.colorScheme.outline,
                              fontWeight: i == 6 - (7 - DateTime.now().weekday) // today
                                  ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                workoutDays.length >= 2
                  ? '本周训练 $workoutDays 天 → 同步查看训练频率与体重趋势'
                  : '继续坚持训练，积累足够数据后可看到训练-体重关联趋势',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDietCard(ThemeData theme, _WeeklyReportData data, UserSettingsEntity? us) {
    final entries = data.dailyCalories.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('本周没有饮食记录', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ),
        ),
      );
    }

    final avgCal = entries.fold<double>(0, (s, e) => s + e.value) / entries.length;
    final tdee = us?.tdee();
    final avgDeficit = tdee != null ? tdee - avgCal : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReportStat(label: '记录天数', value: '${entries.length} 天', theme: theme),
                _ReportStat(label: '日均摄入', value: '${avgCal.toInt()} kcal', theme: theme),
                if (avgDeficit != null)
                  _ReportStat(
                    label: avgDeficit > 0 ? '日均缺口' : '日均超标',
                    value: '${avgDeficit.abs().toInt()} kcal',
                    color: avgDeficit > 0 ? Colors.green : Colors.red,
                    theme: theme,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyReportData {
  final List<BodyMetricEntity> weekMetrics;
  final List<WorkoutEntity> weekWorkouts;
  final Map<DateTime, double> dailyCalories;

  const _WeeklyReportData({
    this.weekMetrics = const [],
    this.weekWorkouts = const [],
    this.dailyCalories = const {},
  });
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final ThemeData theme;
  const _ReportStat({required this.label, required this.value, this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? theme.colorScheme.onSurface,
          )),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }
}
