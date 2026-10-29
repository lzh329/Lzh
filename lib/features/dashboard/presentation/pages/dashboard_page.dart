import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/guga_puppet.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/photo_compare_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/sick_day_banner.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_tasks_card.dart';

/// 主控页 —— v6「任务 + 对比」极简版
///
/// 结构：问候（咕嘎小头像）→ 今日任务（记录体重 / 完成训练 / 记录饮食）
///      → 身体变化对比（最早 vs 最新照片）
/// 统计类信息（体重曲线、热量、饮水、训练量、周报）统一在「趋势」页。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);

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
        data: (data) => _DashboardBody(data: data),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  final DashboardData data;

  const _DashboardBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = data.latestMetric;
    final today = DateTime.now();

    // ── 派生数据 ──
    final currentJin = latest != null ? latest.weightKg * 2 : null;
    final startJin =
        data.firstMetric != null ? data.firstMetric!.weightKg * 2 : null;
    final totalLossJin =
        (startJin != null && currentJin != null) ? startJin - currentJin : 0.0;

    // 连续打卡（体重或训练任一有记录算一天）
    final streak = _calcStreak([
      ...data.allMetrics.map((m) => m.date),
      ...data.allWorkouts.map((w) => w.date),
    ]);

    // 咕嘎形态（问候区小头像 + 距升级提示）
    final guga = GugaLevelService.resolve(totalLossJin);

    final todayWorkouts =
        data.allWorkouts.where((w) => _sameDay(w.date, today)).toList();

    // 今日完成度（用于咕嘎台词）
    final doneCount = [
      data.todayMetric != null,
      todayWorkouts.isNotEmpty,
      data.todayPhoto != null,
    ].where((d) => d).length;

    // 今日训练安排（计划排期）
    final activePlan = data.activePlan;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          // 0) 生病模式横幅（不生效时自己渲染成 0 高度占位，不留空档）
          const SickDayBanner(),
          const SizedBox(height: 10),
          // 1) 问候 + 连续打卡 + 咕嘎小头像
          GreetingHeader(
            streakDays: streak,
            avatarAsset: guga.stage.asset,
            gugaName: guga.stage.name,
            upgradeHint: guga.isMax
                ? null
                : '距升级 ${guga.remainToNext!.toStringAsFixed(1)} 斤',
          ),
          const SizedBox(height: 10),

          // 2) 咕嘎站立区（独立卡片 + 呼吸空间，首屏主角；点头像找 AI 教练）
          //
          // 需求 #11：咕嘎放大 30%（150 → 195），并给它独立的呼吸空间；
          // 「今日打卡」下移到首屏之下，首屏让给问候语 + 咕嘎。
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: GugaPuppet(
                  headAsset: guga.stage.asset.replaceFirst('.png', '_head.png'),
                  bodyAsset: guga.stage.asset.replaceFirst('.png', '_body.png'),
                  height: 195,
                  lines: const [
                    '点我聊聊，我在听',
                    '今天吃啥好？问我',
                    '训练有疑问？戳我',
                  ],
                  lineIndex: doneCount == 0 ? 0 : (doneCount == 3 ? 2 : 1),
                  isChatEntry: true,
                  onTap: () => context.push('/ai/coach'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 3) 今日任务（打卡方块，下移到首屏之下）
          TodayTasksCard(
            todayWeightJin: data.todayMetric != null
                ? data.todayMetric!.weightKg * 2
                : null,
            latestWeightJin: currentJin,
            hasTraining: activePlan != null,
            workoutCount: todayWorkouts.length,
            photoDone: data.todayPhoto != null,
            gugaAsset: guga.stage.asset,
            onWeight: () => context.push('/body'),
            onWorkout: () {
              if (activePlan != null) {
                context.push('/plan/${activePlan.id}/execute');
              } else {
                context.push('/workout/quick-start');
              }
            },
            onPhoto: () => _capturePhoto(context, ref),
          ),
          const SizedBox(height: 14),

          // 3) 身体变化对比（最早 vs 最新）
          PhotoCompareCard(
            firstPath: data.firstPhoto?.filePath,
            firstDate: data.firstPhoto?.date,
            latestPath: data.latestPhoto?.filePath,
            latestDate: data.latestPhoto?.date,
            lossJin: totalLossJin > 0 ? totalLossJin : null,
            onTap: () => context.push('/body/compare'),
          ),
        ],
      ),
    );
  }
}

// ───────────── 辅助函数 ─────────────

/// 首页「今日图片」：拍照并保存为身体照片
Future<void> _capturePhoto(BuildContext context, WidgetRef ref) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 2000,
    imageQuality: 92,
  );
  if (file == null) return;

  await ref.read(photoRepoProvider).addPhoto(
        date: DateTime.now(),
        imageFile: File(file.path),
      );
  ref.invalidate(dashboardDataProvider);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今日图片已记录')),
    );
  }
}

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
