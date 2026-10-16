import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/weight_analysis.dart';
import 'package:fittrack/core/widgets/info_link_card.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/calendar_widget.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/recent_workouts_section.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/weight_hero_card.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

/// 主控页 —— 减脂仪表盘（v2）
///
/// 结构：月历 → 最新体重卡 → 快速入口（热量/饮水/月对比/周报）→ 最近训练
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);
    final settings = ref.watch(userSettingsProvider).valueOrNull;

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
      floatingActionButton: const _WeighInFab(),
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

    // ── 派生指标 ──
    final currentJin = latest != null ? latest.weightKg * 2 : null;
    final targetJin = settings?.targetWeightKg != null
        ? settings!.targetWeightKg! * 2
        : null;
    final totalLossJin =
        (data.firstMetric != null && latest != null && data.firstMetric!.id != latest.id)
            ? data.firstMetric!.weightKg * 2 - currentJin!
            : null;
    final daysToTarget =
        WeightAnalysis.predictDaysToTarget(data.allMetrics, settings?.targetWeightKg);
    final bmi =
        (latest != null && settings != null) ? settings!.bmi(latest.weightKg) : null;

    // ── 热量 ──
    final calorieTarget = settings?.dailyCalorieTarget ?? settings?.tdee()?.round();
    final todayCalories = data.todayCalories?.round();
    final String calorieSubtitle;
    if (todayCalories != null) {
      calorieSubtitle = calorieTarget != null
          ? '已摄入 $todayCalories / $calorieTarget kcal'
          : '已摄入 $todayCalories kcal';
    } else {
      calorieSubtitle = '今天还没有记录饮食，去记录 →';
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 110),
      children: [
        // ── 月历卡 ──
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: CalendarWidget(
              workoutDates: data.calendarWorkoutDates,
              weighInDates: data.weighInDates,
              onDayTap: (date) =>
                  _showDayDetail(context, date, data.allWorkouts, data.exerciseNames),
            ),
          ),
        ),

        // ── 最新体重卡 ──
        WeightHeroCard(
          currentJin: currentJin,
          targetJin: targetJin,
          totalLossJin: totalLossJin,
          daysToTarget: daysToTarget,
          bmi: bmi,
          recordedAt: latest?.date,
          onTap: () => context.push('/body'),
        ),

        // ── 快速入口 ──
        InfoLinkCard(
          icon: Icons.local_fire_department,
          iconColor: const Color(0xFFFF7043),
          title: '今日热量',
          subtitle: calorieSubtitle,
          onTap: () => context.push('/diet'),
        ),
        InfoLinkCard(
          icon: Icons.water_drop,
          iconColor: const Color(0xFF42A5F5),
          title: '今日饮水',
          subtitle: '${data.todayCups} / 8 杯',
          trailing: SizedBox(
            width: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (data.todayCups / 8).clamp(0.0, 1.0),
                minHeight: 6,
                color: const Color(0xFF42A5F5),
                backgroundColor: const Color(0xFF42A5F5).withAlpha(40),
              ),
            ),
          ),
          onTap: () => context.push('/water'),
        ),
        InfoLinkCard(
          icon: Icons.calendar_view_month,
          iconColor: const Color(0xFFAB47BC),
          title: '月度对比',
          subtitle: totalLossJin != null && totalLossJin > 0.05
              ? '累计 ${totalLossJin.toStringAsFixed(1)} 斤变化'
              : '查看本月体重 · 训练 · 饮食变化',
          onTap: () => context.push('/analysis/monthly'),
        ),
        InfoLinkCard(
          icon: Icons.summarize_outlined,
          iconColor: const Color(0xFF66BB6A),
          title: '本周周报',
          subtitle: '本周训练 ${data.weekWorkoutDays} 天',
          onTap: () => context.push('/analysis/weekly'),
        ),

        const SizedBox(height: 6),

        // ── 最近训练 ──
        RecentWorkoutsSection(
          workouts: data.recentWorkouts,
          exerciseNames: data.exerciseNames,
        ),

        // ── 目标入口（有目标时显示）──
        if (data.goals.isNotEmpty) ...[
          const SizedBox(height: 14),
          Card(
            child: InkWell(
              onTap: () => context.push('/goals'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    const Icon(Icons.flag, size: 20, color: Color(0xFFFFA726)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '目标进度：${data.goals.first.currentValue.toStringAsFixed(0)} / ${data.goals.first.targetValue.toStringAsFixed(0)}（${data.goals.length} 个进行中）',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 20, color: theme.colorScheme.outline),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 点击日历某天：底部弹层展示当天训练
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
                        size: 18, color: Color(0xFF66BB6A)),
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

/// 记录体重 FAB —— 点击弹出快捷录入
class _WeighInFab extends ConsumerWidget {
  const _WeighInFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayMetric = ref.watch(dashboardDataProvider).valueOrNull?.todayMetric;
    final hasRecorded = todayMetric != null;

    return FloatingActionButton.extended(
      onPressed: () {
        HapticFeedback.mediumImpact();
        _showQuickWeightInput(context, ref, todayMetric);
      },
      backgroundColor: hasRecorded ? const Color(0xFF66BB6A) : null,
      icon: Icon(hasRecorded ? Icons.check_circle : Icons.monitor_weight),
      label: Text(
        hasRecorded
            ? '今日 ${(todayMetric.weightKg * 2).toStringAsFixed(1)} 斤 ✓'
            : '记录体重',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showQuickWeightInput(
    BuildContext context,
    WidgetRef ref,
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
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                existing != null ? '修改今日体重' : '记录今日体重',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now()),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: theme.textTheme.headlineMedium,
                decoration: InputDecoration(
                  labelText: '体重',
                  suffixText: '斤',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withAlpha(80),
                ),
                onSubmitted: (_) => _doSave(ctx, ref, weightCtrl),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _doSave(ctx, ref, weightCtrl),
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
    WidgetRef ref,
    TextEditingController ctrl,
  ) async {
    final weight = double.tryParse(ctrl.text);
    if (weight == null || weight <= 0) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('请输入有效的体重')),
      );
      return;
    }

    final repo = ref.read(bodyMetricRepoProvider);
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final existingEntries = await repo.getAll(from: todayStart, to: today);

    if (existingEntries.isNotEmpty) {
      await repo.update(
        id: existingEntries.first.id,
        date: today,
        weightKg: weight / 2,
      );
    } else {
      await repo.create(date: today, weightKg: weight / 2);
    }

    // 数据变更 → 依赖自动失效刷新（替代手动刷新计数器）
    ref.invalidate(dashboardDataProvider);
    ref.invalidate(userSettingsProvider);

    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('今日 ${weight.toStringAsFixed(1)} 斤 ✓'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
