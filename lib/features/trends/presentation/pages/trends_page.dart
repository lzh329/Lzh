import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/widgets/info_link_card.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/trends/presentation/widgets/goal_progress_card.dart';
import 'package:fittrack/features/trends/presentation/widgets/planet_card.dart';
import 'package:fittrack/features/trends/presentation/widgets/story_cards.dart';
import 'package:fittrack/features/trends/presentation/widgets/weight_chart_card.dart';
import 'package:fittrack/features/trends/presentation/widgets/weight_timeline_card.dart';

/// 趋势页 —— 减脂进程全景（v2）
class TrendsPage extends ConsumerWidget {
  const TrendsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(trendsDataProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('趋势'), centerTitle: false),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(trendsDataProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(trendsDataProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              PlanetCard(totalLossJin: d.totalLossJin),
              GoalProgressCard(data: d),
              WeightTimelineCard(data: d),
              WeightChartCard(metrics: d.metrics),

              // 身体照片入口
              InfoLinkCard(
                icon: Icons.photo_camera_outlined,
                iconColor: const Color(0xFFEC407A),
                title: '身体照片',
                subtitle: '记录体重时可同时录入围度、对比照片',
                trailing: Text(
                  '${d.photoCount} 张',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                onTap: () => context.push('/body'),
              ),

              const SizedBox(height: 6),

              // 情感化 + 分析
              StoryCard(data: d),
              EffectAnalysisCard(data: d),
              WeekOverviewCard(data: d),

              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('分析报告', style: theme.textTheme.titleMedium),
              ),
              InfoLinkCard(
                icon: Icons.summarize_outlined,
                iconColor: const Color(0xFF66BB6A),
                title: '周报',
                subtitle: '本周训练天数 · 饮食总结',
                onTap: () => context.push('/analysis/weekly'),
              ),
              InfoLinkCard(
                icon: Icons.calendar_view_month,
                iconColor: const Color(0xFFAB47BC),
                title: '月度对比',
                subtitle: '月度体重 · 训练 · 饮食变化对比',
                onTap: () => context.push('/analysis/monthly'),
              ),
              InfoLinkCard(
                icon: Icons.ios_share,
                iconColor: const Color(0xFFFFA726),
                title: '减脂战报',
                subtitle: '生成包含体重变化和照片的分享卡片',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('减脂战报即将上线')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
