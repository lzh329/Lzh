import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

const _green = AppColors.primary;
const _amber = AppColors.warning;
const _orange = AppColors.warning;
const _blue = AppColors.info;
const _red = AppColors.danger;

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
        title: Text(
            '${DateFormat('M月d日').format(monday)} - ${DateFormat('M月d日').format(sunday)} 周报'),
      ),
      body: FutureBuilder<_WeeklyReportData>(
        future: _loadData(bodyRepo, workoutRepo, dietRepo, monday, sunday),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _WeeklyReportData();
          final us = userSettingsAsync.valueOrNull;

          final weekDelta = data.weekMetrics.length >= 2
              ? (data.weekMetrics.last.weightKg -
                      data.weekMetrics.first.weightKg) *
                  2
              : null;
          final workoutDayCount = data.weekWorkouts
              .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
              .toSet()
              .length;
          final calEntries =
              data.dailyCalories.entries.where((e) => e.value > 0).toList();
          final avgCal = calEntries.isEmpty
              ? null
              : calEntries.fold<double>(0, (s, e) => s + e.value) /
                  calEntries.length;

          if (data.weekMetrics.isEmpty && data.weekWorkouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_graph,
                      size: 64, color: AppColors.textTertiary),
                  const SizedBox(height: 16),
                  Text('本周还没有数据',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: 4),
                  Text('记录体重和训练后，周报自动生成',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textTertiary)),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── 核心数据三宫格 ──
              Row(
                children: [
                  _TriCell(
                    label: '体重变化',
                    value: weekDelta != null
                        ? '${weekDelta < -0.05 ? '' : (weekDelta > 0.05 ? '+' : '')}${weekDelta.toStringAsFixed(1)}'
                        : '—',
                    unit: '斤',
                    color: weekDelta == null
                        ? AppColors.textTertiary
                        : (weekDelta < -0.05
                            ? AppColors.success
                            : (weekDelta > 0.05
                                ? _red
                                : AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  _TriCell(
                    label: '训练天数',
                    value: '$workoutDayCount',
                    unit: '/7 天',
                    color: AppColors.textPrimary,
                  ),
                  const SizedBox(width: 8),
                  _TriCell(
                    label: '日均摄入',
                    value: avgCal != null ? '${avgCal.toInt()}' : '—',
                    unit: 'kcal',
                    color: _orange,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 体重变化 ──
              if (data.weekMetrics.length >= 2) ...[
                const _SectionTitle(
                    icon: Icons.monitor_weight, title: '体重', color: _amber),
                const SizedBox(height: 8),
                _buildWeightCard(theme, data, us),
                const SizedBox(height: 20),
              ],

              // ── 训练 ──
              const _SectionTitle(
                  icon: Icons.fitness_center, title: '训练', color: _green),
              const SizedBox(height: 8),
              _buildTrainingCard(theme, data),
              const SizedBox(height: 20),

              // ── 训练-体重关联 ──
              if (data.weekWorkouts.isNotEmpty &&
                  data.weekMetrics.isNotEmpty) ...[
                const _SectionTitle(
                    icon: Icons.insights, title: '训练-体重关联', color: _blue),
                const SizedBox(height: 8),
                _buildCorrelationChart(theme, data),
                const SizedBox(height: 20),
              ],

              // ── 饮食 ──
              const _SectionTitle(
                  icon: Icons.restaurant, title: '饮食', color: _orange),
              const SizedBox(height: 8),
              _buildDietCard(theme, data, us),
              const SizedBox(height: 20),

              // ── 本周点评 ──
              _buildReviewCard(
                  theme, data, us, weekDelta, workoutDayCount, avgCal),
              const SizedBox(height: 14),

              // ── 分享 ──
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('减脂战报即将上线')),
                    );
                  },
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('分享本周战报', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(color: _green.withAlpha(90)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_WeeklyReportData> _loadData(
      repos, workoutRepo, dietRepo, monday, sunday) async {
    final weekMetrics = await repos.getAll(from: monday, to: sunday);
    final weekWorkouts = await workoutRepo.getAll(from: monday, to: sunday);

    // 本周每日热量
    final dailyCals = <DateTime, double>{};
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(DateTime.now())) break;
      dailyCals[DateTime(day.year, day.month, day.day)] =
          await dietRepo.getDailyCalories(day);
    }

    return _WeeklyReportData(
      weekMetrics: weekMetrics,
      weekWorkouts: weekWorkouts,
      dailyCalories: dailyCals,
    );
  }

  Widget _buildWeightCard(
      ThemeData theme, _WeeklyReportData data, UserSettingsEntity? us) {
    final first = data.weekMetrics.first;
    final last = data.weekMetrics.last;
    final delta = (last.weightKg - first.weightKg) * 2;
    final isDown = delta < -0.05;
    final isUp = delta > 0.05;
    final arrow = isDown
        ? '↓'
        : isUp
            ? '↑'
            : '→';
    final deltaColor = isDown
        ? AppColors.success
        : isUp
            ? AppColors.danger
            : AppColors.textTertiary;

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
                _ReportStat(
                    label: '周初',
                    value: '${(first.weightKg * 2).toStringAsFixed(1)} 斤',
                    theme: theme),
                Icon(Icons.arrow_forward, color: deltaColor, size: 20),
                _ReportStat(
                    label: '周末',
                    value: '${(last.weightKg * 2).toStringAsFixed(1)} 斤',
                    theme: theme),
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
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary)),
                if (weeklyRate.abs() >= 0.5 && weeklyRate.abs() <= 2.0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.success.withAlpha(25),
                        borderRadius: BorderRadius.circular(4)),
                    child: const Text('✓ 健康区间',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
            if (us?.targetWeightKg != null) ...[
              const SizedBox(height: 8),
              Text(
                  '距目标 ${(us!.targetWeightKg! * 2).toStringAsFixed(1)} 斤 · 还差 ${((last.weightKg - us.targetWeightKg!) * 2).toStringAsFixed(1)} 斤',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.primaryText)),
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
    final totalSets =
        data.weekWorkouts.fold<int>(0, (sum, w) => sum + w.totalSets);
    final totalDurationMin = data.weekWorkouts
            .fold<int>(0, (sum, w) => sum + (w.durationSec ?? 0)) ~/
        60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ReportStat(
                    label: '训练天数',
                    value: '${workoutDays.length} / 7 天',
                    theme: theme),
                _ReportStat(label: '完成组数', value: '$totalSets 组', theme: theme),
                if (totalDurationMin > 0)
                  _ReportStat(
                      label: '训练时长',
                      value: '$totalDurationMin 分钟',
                      theme: theme),
              ],
            ),
            if (data.weekWorkouts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('本周没有训练记录',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary)),
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

    if (weightByDay.length < 2 && workoutDays.isEmpty) {
      return const SizedBox.shrink();
    }

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
                Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: AppColors.info, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('体重',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.info)),
                const SizedBox(width: 16),
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('训练日',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.primaryText)),
                const Spacer(),
                Text(
                    '${minW.toStringAsFixed(1)} - ${maxW.toStringAsFixed(1)} kg',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary)),
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
                  final normalized =
                      hasWeight ? ((w! - minW) / wRange).clamp(0.0, 1.0) : 0.0;

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
                                color: AppColors.info,
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(3)),
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
                          Text(
                            dayLabels[i],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DateTime.now().weekday == (i + 1) % 7 + 1
                                  ? AppColors.primaryText
                                  : AppColors.textTertiary,
                              fontWeight:
                                  i == 6 - (7 - DateTime.now().weekday) // today
                                      ? FontWeight.bold
                                      : FontWeight.normal,
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDietCard(
      ThemeData theme, _WeeklyReportData data, UserSettingsEntity? us) {
    final entries =
        data.dailyCalories.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text('本周没有饮食记录',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.textTertiary)),
          ),
        ),
      );
    }

    final avgCal =
        entries.fold<double>(0, (s, e) => s + e.value) / entries.length;
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
                _ReportStat(
                    label: '记录天数', value: '${entries.length} 天', theme: theme),
                _ReportStat(
                    label: '日均摄入',
                    value: '${avgCal.toInt()} kcal',
                    theme: theme),
                if (avgDeficit != null)
                  _ReportStat(
                    label: avgDeficit > 0 ? '日均缺口' : '日均超标',
                    value: '${avgDeficit.abs().toInt()} kcal',
                    color:
                        avgDeficit > 0 ? AppColors.success : AppColors.danger,
                    theme: theme,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 本周点评（规则生成的文字分析）
  Widget _buildReviewCard(
    ThemeData theme,
    _WeeklyReportData data,
    UserSettingsEntity? us,
    double? weekDelta,
    int workoutDays,
    double? avgCal,
  ) {
    final lines = <String>[];

    if (weekDelta == null) {
      lines.add('本周体重记录不足 2 条，继续记录才能看到趋势。');
    } else if (weekDelta < -0.05) {
      lines.add('体重本周下降 ${weekDelta.abs().toStringAsFixed(1)} 斤。');
      if (workoutDays >= 3) {
        lines.add('训练 $workoutDays 天，频率保持得不错，继续保持这个节奏。');
      } else {
        lines.add('训练只有 $workoutDays 天，如果能增加到 3 天以上，减脂会更稳。');
      }
    } else if (weekDelta > 0.05) {
      lines.add('体重本周回升 ${weekDelta.toStringAsFixed(1)} 斤，先别焦虑，可能包含水分波动。');
      lines.add('注意晚餐碳水量，保持训练频率，下周继续观察趋势。');
    } else {
      lines.add('体重基本持平，可能处于平台期。');
      lines.add('可以尝试调整训练强度或饮食结构，打破平衡。');
    }

    final tdee = us?.tdee();
    if (avgCal != null && tdee != null && avgCal > tdee) {
      lines.add('日均摄入比消耗高 ${(avgCal - tdee).toInt()} kcal，建议控制加餐。');
    }
    if (workoutDays == 0) {
      lines.add('本周还没有训练记录，从 10 分钟开始也比不动强。');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text('本周点评', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TriCell extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _TriCell({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: color),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    ' $unit',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
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
  final Color color;
  const _SectionTitle({
    required this.icon,
    required this.title,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: color.withAlpha(32),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ReportStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final ThemeData theme;
  const _ReportStat(
      {required this.label,
      required this.value,
      this.color,
      required this.theme});

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
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }
}
