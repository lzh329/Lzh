import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/core/services/weight_analysis.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/photo_compare_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_training_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_weight_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/weigh_in_fab.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 主控页 —— v5「训练优先」布局
///
/// 结构：问候（咕嘎小头像）→ 今日训练（一键开始）→ 体重记录
///      → 身体变化对比（最早 vs 最新）→ 今日小字（热量 / 饮水 / 饮食）
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
    final latest = data.latestMetric;
    final today = DateTime.now();

    // ── 派生数据 ──
    final currentJin = latest != null ? latest.weightKg * 2 : null;
    final targetJin = settings?.targetWeightKg != null
        ? settings!.targetWeightKg! * 2
        : null;
    final startJin =
        data.firstMetric != null ? data.firstMetric!.weightKg * 2 : null;
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

    // 咕嘎形态（问候区小头像 + 距升级提示）
    final totalLossJin =
        (startJin != null && currentJin != null) ? startJin - currentJin : 0.0;
    final guga = GugaLevelService.resolve(totalLossJin);

    // ── 今日训练卡内容 ──
    final activePlan = data.activePlan;
    final planItems = data.todayPlanItems;
    final itemLabels = planItems
        .map((d) =>
            '${data.exerciseNames[d.exerciseId] ?? '动作 #${d.exerciseId}'} ${d.targetSets} 组')
        .toList();
    final dayLabel = activePlan != null && planItems.isNotEmpty
        ? '${_weekdayLabel(today.weekday)} · 排期'
        : null;

    // ── 照片对比 ──
    final photoLoss =
        (startJin != null && currentJin != null) ? startJin - currentJin : null;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          // 1) 问候 + 连续打卡 + 咕嘎小头像
          GreetingHeader(
            streakDays: streak,
            avatarAsset: guga.stage.asset,
            gugaName: guga.stage.name,
            upgradeHint: guga.isMax
                ? null
                : '距升级 ${guga.remainToNext!.toStringAsFixed(1)} 斤',
          ),
          const SizedBox(height: 22),

          // 2) 今日训练（训练优先）
          TodayTrainingCard(
            planName: activePlan?.name,
            dayLabel: dayLabel,
            itemLabels: itemLabels,
            hasPlan: activePlan != null,
            onStart: () {
              if (activePlan != null) {
                context.push('/plan/${activePlan.id}/execute');
              }
            },
            onBrowse: () => context.push('/workout/quick-start'),
          ),
          const SizedBox(height: 12),

          // 3) 体重记录
          TodayWeightCard(
            currentJin: currentJin,
            weekChangeJin: weekChange,
            targetJin: targetJin,
            progress: progress,
            lastRecordedAt: data.todayMetric?.date ?? latest?.date,
            onRecord: () => context.push('/body'),
            onTap: () => context.push('/body'),
          ),
          const SizedBox(height: 12),

          // 4) 身体变化对比（照片显眼入口）
          PhotoCompareCard(
            firstPath: data.firstPhoto?.filePath,
            firstDate: data.firstPhoto?.date,
            latestPath: data.latestPhoto?.filePath,
            latestDate: data.latestPhoto?.date,
            lossJin: photoLoss,
            onTap: () => context.push('/body/album'),
          ),
          const SizedBox(height: 18),

          // 5) 今日小字：热量 / 饮水 / 饮食
          _MiniStatsRow(
            calories: data.todayCalories,
            cups: data.todayCups,
            hasDiet: data.todayCalories != null,
            onCalories: () => context.push('/diet'),
            onWater: () => context.push('/water'),
          ),
        ],
      ),
    );
  }
}

/// 底部一行小字（热量 / 饮水 / 饮食），点击跳转
class _MiniStatsRow extends StatelessWidget {
  final double? calories;
  final int cups;
  final bool hasDiet;
  final VoidCallback onCalories;
  final VoidCallback onWater;

  const _MiniStatsRow({
    required this.calories,
    required this.cups,
    required this.hasDiet,
    required this.onCalories,
    required this.onWater,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MiniStat(
          icon: Icons.local_fire_department_outlined,
          text: calories != null ? '${calories!.round()} kcal' : '饮食未记录',
          color: const Color(0xFFFFC53D),
          outline: outline,
          onTap: onCalories,
        ),
        _MiniStat(
          icon: Icons.water_drop_outlined,
          text: '$cups 杯水',
          color: const Color(0xFF38BDF8),
          outline: outline,
          onTap: onWater,
        ),
        _MiniStat(
          icon: Icons.restaurant_outlined,
          text: hasDiet ? '饮食已记录' : '记录饮食',
          color: const Color(0xFFFF8A00),
          outline: outline,
          onTap: onCalories,
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color outline;
  final VoidCallback onTap;

  const _MiniStat({
    required this.icon,
    required this.text,
    required this.color,
    required this.outline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(fontSize: 10.5, color: outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────── 辅助函数 ─────────────

String _weekdayLabel(int w) =>
    const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][w - 1];

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
