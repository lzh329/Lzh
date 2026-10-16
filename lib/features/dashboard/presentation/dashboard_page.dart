import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'widgets/calendar_widget.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userSettingsAsync = ref.watch(userSettingsProvider);
    final dashboardAsync = ref.watch(dashboardDataProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('简瘦'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.fitness_center),
            tooltip: '开始训练',
            onPressed: () {
              HapticFeedback.mediumImpact();
              context.push('/workout/quick-start');
            },
          ),
        ],
      ),
      body: dashboardAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('加载失败')),
        data: (data) {

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CalendarWidget(
                workoutDates: data.calendarWorkoutDates,
                weighInDates: data.weighInDates,
                onDayTap: (date) => _showDayDetail(context, date, data.allWorkouts, data.exerciseNames),
              ),
              const SizedBox(height: 12),
              _SummaryBanner(data: data, userSettings: userSettingsAsync.valueOrNull),
              const SizedBox(height: 12),
              _WeightCard(
                latestMetric: data.latestMetric,
                firstMetric: data.firstMetric,
                weekStartMetric: data.weekStartMetric,
                allMetrics: data.allMetrics,
                userSettings: userSettingsAsync.valueOrNull,
              ),
              const SizedBox(height: 12),
              _CalorieCard(
                todayCalories: data.todayCalories,
                userSettings: userSettingsAsync.valueOrNull,
                onTap: () => context.go('/diet'),
              ),
              const SizedBox(height: 16),
              _GoalsCard(goals: data.goals),
              const SizedBox(height: 12),
              _CorrelationHint(data: data),
              const SizedBox(height: 12),
              _WaterCard(todayCups: data.todayCups),
              const SizedBox(height: 12),
              _MonthlyCompareMiniCard(data: data),
              const SizedBox(height: 8),
              _WeeklyReportMiniCard(data: data),
              const SizedBox(height: 16),
              Text('最近训练', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (data.recentWorkouts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('还没有训练记录\n点击右上角 🏋️ 开始', textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  ),
                )
              else
                ...data.recentWorkouts.take(3).map((w) => _WorkoutCard(workout: w, exerciseNames: data.exerciseNames)),
            ],
          );
        },
      ),
      floatingActionButton: _WeighInFab(
        bodyRepo: ref.watch(bodyMetricRepoProvider),
      ),
    );
  }

  /// 点击日历某一天：展示该日训练记录
  void _showDayDetail(
    BuildContext context,
    DateTime date,
    List<WorkoutEntity> allWorkouts,
    Map<int, String> exerciseNames,
  ) {
    final dayWorkouts = allWorkouts.where((w) =>
        w.date.year == date.year &&
        w.date.month == date.month &&
        w.date.day == date.day).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final dateFmt = DateFormat('M月d日 EEEE', 'zh_CN');

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(dateFmt.format(date), style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (dayWorkouts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('当天没有训练记录',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      )),
                  ),
                )
              else
                ...dayWorkouts.map((w) => _WorkoutCard(workout: w, exerciseNames: exerciseNames)),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _WeightCard extends StatelessWidget {
  final BodyMetricEntity? latestMetric;
  final BodyMetricEntity? firstMetric;
  final BodyMetricEntity? weekStartMetric;
  final List<BodyMetricEntity> allMetrics;
  final UserSettingsEntity? userSettings;

  const _WeightCard({
    required this.latestMetric,
    required this.firstMetric,
    required this.weekStartMetric,
    required this.allMetrics,
    required this.userSettings,
  });

  Color? _bmiBgColor(ThemeData theme) {
    if (latestMetric == null || userSettings?.heightCm == null) return null;
    final bmi = userSettings!.bmi(latestMetric!.weightKg);
    if (bmi == null) return null;
    final level = UserSettingsEntity.bmiLevel(bmi);
    switch (level) {
      case 'normal':
        return Colors.green.withAlpha(30);
      case 'overweight':
        return Colors.orange.withAlpha(45);
      case 'obese':
        return Colors.red.withAlpha(45);
      default:
        return Colors.blue.withAlpha(25);
    }
  }

  Color? _bmiIconColor(ThemeData theme) {
    if (latestMetric == null || userSettings?.heightCm == null) return null;
    final bmi = userSettings!.bmi(latestMetric!.weightKg);
    if (bmi == null) return null;
    final level = UserSettingsEntity.bmiLevel(bmi);
    switch (level) {
      case 'normal': return Colors.green;
      case 'overweight': return Colors.orange;
      case 'obese': return Colors.red;
      default: return Colors.blue;
    }
  }

  /// 线性回归预测：距目标体重还有多少天
  int? _predictDaysToTarget() {
    if (allMetrics.length < 3) return null;
    final targetKg = userSettings?.targetWeightKg;
    if (targetKg == null) return null;

    final n = allMetrics.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = allMetrics[i].weightKg;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return null;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;

    // 斜率接近 0（体重不变）→ 无法预测
    if (slope.abs() < 0.001) return null;

    final lastX = (n - 1).toDouble();
    final days = ((targetKg - intercept) / slope - lastX).round();

    // 减脂方向：斜率应为负（体重下降）。如果斜率 > 0 说明在增重，也给出预测
    if (days <= 0 || days > 365) return null;
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = _bmiBgColor(theme);
    final iconColor = _bmiIconColor(theme);

    // 无数据
    if (latestMetric == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.monitor_weight, size: 40, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text('暂无体重数据', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 4),
                Text('去「体重」Tab 录入第一条数据', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        ),
      );
    }

    final currentJin = latestMetric!.weightKg * 2;
    final targetJin = userSettings?.targetWeightKg != null ? userSettings!.targetWeightKg! * 2 : null;

    // ── 计算本周变化 ──
    final weekChange = (weekStartMetric != null && weekStartMetric!.id != latestMetric!.id)
      ? currentJin - weekStartMetric!.weightKg * 2
      : null;

    // ── 累计减重 ──
    final totalLoss = (firstMetric != null && firstMetric!.id != latestMetric!.id)
      ? firstMetric!.weightKg * 2 - currentJin
      : null;

    // ── 预测 ──
    final predictDays = _predictDaysToTarget();

    // ── 体重变化方向色 ──
    Color changeColor(double diff) {
      if (diff < -0.05) return Colors.green;   // 下降 = 好
      if (diff > 0.05) return Colors.red;      // 上升
      return theme.colorScheme.outline;          // 几乎不变
    }

    String changeArrow(double diff) {
      if (diff < -0.05) return '↓';
      if (diff > 0.05) return '↑';
      return '→';
    }

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── 第一行：体重 + BMI 徽章 ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.monitor_weight, size: 36,
                  color: iconColor ?? theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('最新体重', style: theme.textTheme.titleMedium),
                          if (iconColor != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: iconColor.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'BMI ${userSettings?.heightCm != null ? userSettings!.bmi(latestMetric!.weightKg)!.toStringAsFixed(1) : "—"}',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: iconColor),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${currentJin.toStringAsFixed(1)} 斤',
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        DateFormat('MM月dd日').format(latestMetric!.date),
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // ── 分隔线 ──
            if (weekChange != null || totalLoss != null || predictDays != null) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.colorScheme.outline.withAlpha(30)),
              const SizedBox(height: 10),
            ],

            // ── 第二行：减脂指标 ──
            if (weekChange != null || totalLoss != null || predictDays != null)
              Row(
                children: [
                  // 本周变化
                  if (weekChange != null)
                    _Indicator(
                      icon: Icons.trending_down,
                      label: '本周',
                      value: '${changeArrow(weekChange)} ${weekChange.abs().toStringAsFixed(1)} 斤',
                      color: changeColor(weekChange),
                    ),
                  if (weekChange != null && totalLoss != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(width: 1, height: 28, color: theme.colorScheme.outline.withAlpha(40)),
                    ),
                  // 累计减重
                  if (totalLoss != null)
                    _Indicator(
                      icon: Icons.emoji_events,
                      label: '累计减重',
                      value: '${totalLoss.toStringAsFixed(1)} 斤',
                      color: totalLoss > 0.05 ? Colors.green : theme.colorScheme.outline,
                    ),
                  if ((weekChange != null || totalLoss != null) && predictDays != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Container(width: 1, height: 28, color: theme.colorScheme.outline.withAlpha(40)),
                    ),
                  // 目标倒计时
                  if (predictDays != null)
                    Expanded(
                      child: _Indicator(
                        icon: Icons.flag,
                        label: '预计达成',
                        value: '$predictDays 天后',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),

            // ── 目标体重条 ──
            if (targetJin != null && predictDays != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('距目标 $targetJin 斤', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  const Spacer(),
                  Text('还差 ${(currentJin - targetJin).toStringAsFixed(1)} 斤',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ] else if (targetJin != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.flag, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('目标 $targetJin 斤 · 还差 ${(currentJin - targetJin).toStringAsFixed(1)} 斤',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  if (allMetrics.length < 3)
                    Text('（需 3 条以上体重记录才能预测）',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline.withAlpha(150), fontSize: 10)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 减脂卡片内的迷你指标
class _Indicator extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _Indicator({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
      ],
    );
  }
}

/// 首页热量缺口卡片
class _CalorieCard extends StatelessWidget {
  final double? todayCalories;
  final UserSettingsEntity? userSettings;
  final VoidCallback onTap;

  const _CalorieCard({
    required this.todayCalories,
    required this.userSettings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tdee = userSettings?.tdee();

    // 未设置身体信息
    if (tdee == null) {
      return Card(
        child: InkWell(
          onTap: () => context.push('/settings/body-info'),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.local_fire_department, size: 24, color: theme.colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('设置身体信息后计算热量缺口',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                ),
                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      );
    }

    // 未记录饮食
    if (todayCalories == null) {
      return Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.restaurant, size: 24, color: theme.colorScheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('今日热量', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text('今天还没有记录饮食 · 去饮食Tab记录',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      );
    }

    final deficit = tdee - todayCalories!;
    final isDeficit = deficit > 0;
    final deficitColor = isDeficit ? Colors.green : Colors.red;
    final deficitIcon = isDeficit ? Icons.trending_down : Icons.trending_up;
    final deficitLabel = isDeficit ? '热量缺口' : '热量超标';

    // 减脂热量目标（TDEE × 0.8）
    final calorieTarget = (tdee * 0.8).toInt();

    // 消耗百分比进度
    final percent = (todayCalories! / tdee).clamp(0.0, 1.5);
    final progressColor = percent <= 0.85
      ? Colors.green
      : percent <= 1.0
        ? Colors.orange
        : Colors.red;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('今日热量', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 12),
              // 进度条
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent > 1.0 ? 1.0 : percent,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: progressColor,
                ),
              ),
              const SizedBox(height: 8),
              // 数字行
              Row(
                children: [
                  _CalorieStat(
                    icon: Icons.restaurant,
                    label: '摄入',
                    value: '${todayCalories!.toInt()}',
                    unit: 'kcal',
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(width: 4),
                  Text('|', style: TextStyle(color: theme.colorScheme.outline.withAlpha(60))),
                  const SizedBox(width: 4),
                  _CalorieStat(
                    icon: Icons.flag,
                    label: '限额',
                    value: '$calorieTarget',
                    unit: 'kcal',
                    color: todayCalories! <= calorieTarget ? Colors.green : Colors.red,
                  ),
                  const Spacer(),
                  _CalorieStat(
                    icon: deficitIcon,
                    label: deficitLabel,
                    value: '${deficit.abs().toInt()}',
                    unit: 'kcal',
                    color: deficitColor,
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

/// 热量卡内的迷你数值
class _CalorieStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _CalorieStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color.withAlpha(180)),
            const SizedBox(width: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 1),
              child: Text(unit, style: TextStyle(fontSize: 10, color: color.withAlpha(180))),
            ),
          ],
        ),
      ],
    );
  }
}

/// 首页浮动称重按钮（自加载今日体重）
class _WeighInFab extends ConsumerStatefulWidget {
  final BodyMetricRepository bodyRepo;

  const _WeighInFab({required this.bodyRepo});

  @override
  ConsumerState<_WeighInFab> createState() => _WeighInFabState();
}

class _WeighInFabState extends ConsumerState<_WeighInFab> {
  BodyMetricEntity? _todayMetric;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadToday();
  }

  Future<void> _loadToday() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final metrics = await widget.bodyRepo.getAll(from: todayStart, to: now);
    if (mounted) {
      setState(() {
        _todayMetric = metrics.isNotEmpty ? metrics.first : null;
        _loaded = true;
      });
    }
  }

  void _onSaved() {
    ref.read(dashboardRefreshCount.notifier).state++;
    _loadToday();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(dashboardRefreshCount);
    if (!_loaded) {
      return const FloatingActionButton.extended(
        onPressed: null,
        icon: Icon(Icons.monitor_weight),
        label: Text('记录体重'),
      );
    }

    final hasRecorded = _todayMetric != null;

    return FloatingActionButton.extended(
      onPressed: () {
        HapticFeedback.mediumImpact();
        _showQuickWeightInput(context, widget.bodyRepo, _onSaved, _todayMetric);
      },
      backgroundColor: hasRecorded ? Colors.green : null,
      icon: Icon(hasRecorded ? Icons.check_circle : Icons.monitor_weight),
      label: Text(
        hasRecorded
          ? '今日 ${(_todayMetric!.weightKg * 2).toStringAsFixed(1)} 斤 ✓'
          : '记录体重',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showQuickWeightInput(
    BuildContext context,
    BodyMetricRepository bodyRepo,
    VoidCallback onSaved,
    BodyMetricEntity? existing,
  ) {
    final weightCtrl = TextEditingController(
      text: existing != null ? (existing.weightKg * 2).toStringAsFixed(1) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                existing != null ? '修改今日体重' : '记录今日体重',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now()),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightCtrl,
                autofocus: existing == null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: theme.textTheme.headlineMedium,
                decoration: InputDecoration(
                  labelText: '体重',
                  suffixText: '斤',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                ),
                onSubmitted: (_) => _doSave(ctx, bodyRepo, onSaved, weightCtrl),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _doSave(ctx, bodyRepo, onSaved, weightCtrl),
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('保存', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _doSave(
    BuildContext ctx,
    BodyMetricRepository bodyRepo,
    VoidCallback onSaved,
    TextEditingController ctrl,
  ) async {
    final weight = double.tryParse(ctrl.text);
    if (weight == null || weight <= 0) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('请输入有效的体重')));
      return;
    }

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final existingEntries = await bodyRepo.getAll(from: todayStart, to: today);

    if (existingEntries.isNotEmpty) {
      await bodyRepo.update(
        id: existingEntries.first.id,
        date: today,
        weightKg: weight / 2,
      );
    } else {
      await bodyRepo.create(
        date: today,
        weightKg: weight / 2,
      );
    }

    onSaved();
    if (ctx.mounted) Navigator.pop(ctx);
  }
}

class _GoalsCard extends StatelessWidget {
  final List<GoalEntity> goals;
  const _GoalsCard({required this.goals});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (goals.isEmpty) return const SizedBox.shrink();

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed('/goals'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('目标进度', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 8),
              ...goals.take(2).map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(GoalEntity.typeLabels[g.type] ?? g.type,
                          style: theme.textTheme.bodySmall),
                        const Spacer(),
                        Text(
                          '${g.currentValue.toStringAsFixed(g.type == 'weight' ? 1 : 0)}/${g.targetValue.toStringAsFixed(g.type == 'weight' ? 1 : 0)}${g.type == 'weight' ? '斤' : '次'}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: g.progressPercent / 100,
                        minHeight: 6,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              )),
              if (goals.length > 2)
                Text('还有 ${goals.length - 2} 个目标...',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final WorkoutEntity workout;
  final Map<int, String> exerciseNames;
  const _WorkoutCard({required this.workout, required this.exerciseNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exerciseIds = workout.sets.map((s) => s.exerciseId).toSet();
    final names = exerciseIds
        .map((id) => exerciseNames[id] ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
    final title = names.isNotEmpty
        ? '${names.join('、')}  · ${workout.totalSets} 组'
        : '${exerciseIds.length} 个动作 · ${workout.totalSets} 组';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimaryContainer),
        ),
        title: Text(title),
        subtitle: Text(DateFormat('MM月dd日 HH:mm').format(workout.date)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/workout/${workout.id}'),
      ),
    );
  }
}

/// 个性化数据摘要（替代励志标语）
class _SummaryBanner extends StatelessWidget {
  final DashboardData data;
  final UserSettingsEntity? userSettings;

  const _SummaryBanner({required this.data, required this.userSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWeightData = data.latestMetric != null && data.weekStartMetric != null;
    final hasDiet = data.todayCalories != null;

    // 本周训练天数
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekWorkoutDays = data.allWorkouts
        .where((w) => !w.date.isBefore(monday))
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet().length;

    // 本周体重变化
    String? weekDelta;
    if (data.latestMetric != null && data.weekStartMetric != null &&
        data.latestMetric!.id != data.weekStartMetric!.id) {
      final delta = (data.latestMetric!.weightKg - data.weekStartMetric!.weightKg) * 2;
      if (delta < -0.05) {
        weekDelta = '↓${delta.abs().toStringAsFixed(1)}';
      } else if (delta > 0.05) {
        weekDelta = '↑${delta.toStringAsFixed(1)}';
      } else {
        weekDelta = '→ 持平';
      }
    }

    // 无任何数据
    if (!hasWeightData && weekWorkoutDays == 0 && !hasDiet) {
      return Card(
        color: theme.colorScheme.primaryContainer.withAlpha(80),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('👋', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text('欢迎！先设置目标体重，再记录今天的体重吧',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ),
            ],
          ),
        ),
      );
    }

    // 构建摘要段
    final parts = <Widget>[];
    if (weekDelta != null) {
      parts.add(_SummarySegment(
        icon: Icons.trending_down,
        text: '本周 $weekDelta 斤',
        color: weekDelta.contains('↓') ? Colors.green : weekDelta.contains('↑') ? Colors.red : null,
      ));
    }
    if (weekWorkoutDays > 0) {
      if (parts.isNotEmpty) parts.add(_SummaryDot());
      parts.add(_SummarySegment(icon: Icons.fitness_center, text: '训练 $weekWorkoutDays 天'));
    }
    if (hasDiet && userSettings?.tdee() != null) {
      if (parts.isNotEmpty) parts.add(_SummaryDot());
      final deficit = userSettings!.tdee()! - data.todayCalories!;
      final dLabel = deficit > 0 ? '缺口 ${deficit.toInt()}' : '超标 ${deficit.abs().toInt()}';
      parts.add(_SummarySegment(
        icon: Icons.local_fire_department,
        text: '今日$dLabel kcal',
        color: deficit > 0 ? Colors.green : Colors.red,
      ));
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer.withAlpha(80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(spacing: 6, runSpacing: 2, children: parts),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySegment extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _SummarySegment({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onPrimaryContainer;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: c),
      const SizedBox(width: 2),
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c)),
    ]);
  }
}

class _SummaryDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text('·', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
    );
  }
}

/// 月度对比迷你入口
class _MonthlyCompareMiniCard extends StatelessWidget {
  final DashboardData data;
  const _MonthlyCompareMiniCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.firstMetric == null || data.latestMetric == null) return const SizedBox.shrink();
    if (data.firstMetric!.id == data.latestMetric!.id) return const SizedBox.shrink();

    final totalLoss = (data.firstMetric!.weightKg - data.latestMetric!.weightKg) * 2;
    if (totalLoss <= 0.05) return const SizedBox.shrink();

    final days = data.latestMetric!.date.difference(data.firstMetric!.date).inDays;

    return Card(
      child: InkWell(
        onTap: () => context.push('/analysis/monthly'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Text('📅', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text('月度对比', style: theme.textTheme.titleSmall)),
              Text('累计 ↓${totalLoss.toStringAsFixed(1)}斤 · $days天',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.green, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 饮水追踪卡片
class _WaterCard extends StatelessWidget {
  final int todayCups;
  const _WaterCard({required this.todayCups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const targetCups = 8;
    final cups = todayCups.clamp(0, targetCups + 2);

    return Card(
      child: InkWell(
        onTap: () => context.push('/water'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Text('💧', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('今日饮水', style: theme.textTheme.titleSmall),
                        const SizedBox(width: 8),
                        Text('$cups/$targetCups 杯', style: theme.textTheme.bodySmall?.copyWith(
                          color: cups >= targetCups ? Colors.green : theme.colorScheme.outline,
                          fontWeight: FontWeight.w600,
                        )),
                        if (cups >= targetCups) const Text(' ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (cups / targetCups).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: cups >= targetCups ? Colors.green : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 周报迷你入口卡片
class _WeeklyReportMiniCard extends StatelessWidget {
  final DashboardData data;
  const _WeeklyReportMiniCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String? weekLabel;
    if (data.latestMetric != null && data.weekStartMetric != null &&
        data.latestMetric!.id != data.weekStartMetric!.id) {
      final delta = (data.latestMetric!.weightKg - data.weekStartMetric!.weightKg) * 2;
      if (delta < -0.05) {
        weekLabel = '↓${delta.abs().toStringAsFixed(1)}斤';
      } else if (delta > 0.05) {
        weekLabel = '↑${delta.toStringAsFixed(1)}斤';
      } else {
        weekLabel = '持平';
      }
    }

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekWorkoutDays = data.allWorkouts
        .where((w) => !w.date.isBefore(monday))
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet().length;

    return Card(
      child: InkWell(
        onTap: () => context.push('/analysis/weekly'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '本周周报',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (weekLabel != null) ...[
                Text(weekLabel, style: theme.textTheme.bodySmall?.copyWith(
                  color: weekLabel.contains('↓') ? Colors.green : weekLabel.contains('↑') ? Colors.red : theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                )),
                const SizedBox(width: 4),
                Text('·', style: TextStyle(color: theme.colorScheme.outline)),
                const SizedBox(width: 4),
              ],
              Text('训练$weekWorkoutDays天', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// 训练-体重关联提示
class _CorrelationHint extends StatelessWidget {
  final DashboardData data;
  const _CorrelationHint({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.latestMetric == null || data.weekStartMetric == null) return const SizedBox.shrink();
    if (data.latestMetric!.id == data.weekStartMetric!.id) return const SizedBox.shrink();

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final weekWorkoutDays = data.allWorkouts
        .where((w) => !w.date.isBefore(monday))
        .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
        .toSet().length;

    final weekDeltaJin = (data.latestMetric!.weightKg - data.weekStartMetric!.weightKg) * 2;

    String hint;
    if (weekWorkoutDays >= 3 && weekDeltaJin < -0.1) {
      hint = '💪 本周训练 $weekWorkoutDays 天，体重 ↓${weekDeltaJin.abs().toStringAsFixed(1)} 斤，训练效果显著！';
    } else if (weekWorkoutDays >= 1 && weekDeltaJin < -0.1) {
      hint = '👍 本周训练 $weekWorkoutDays 天，体重 ↓${weekDeltaJin.abs().toStringAsFixed(1)} 斤';
    } else if (weekWorkoutDays == 0 && weekDeltaJin < -0.1) {
      hint = '🎯 本周未训练但体重 ↓${weekDeltaJin.abs().toStringAsFixed(1)} 斤，饮食控制有效！';
    } else if (weekWorkoutDays >= 1 && weekDeltaJin > 0.1) {
      hint = '🤔 本周训练 $weekWorkoutDays 天但体重 ↑${weekDeltaJin.toStringAsFixed(1)} 斤，关注饮食摄入';
    } else if (weekWorkoutDays == 0 && weekDeltaJin > 0.1) {
      hint = '📋 本周未训练，体重 ↑${weekDeltaJin.toStringAsFixed(1)} 斤';
    } else {
      hint = '📊 本周体重持平，继续保持';
    }

    return Card(
      color: theme.colorScheme.tertiaryContainer.withAlpha(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface, height: 1.4)),
      ),
    );
  }
}

