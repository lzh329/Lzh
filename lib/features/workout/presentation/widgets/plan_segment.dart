import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';

final _plansProvider = FutureProvider<List<PlanEntity>>(
  (ref) => ref.watch(planRepoProvider).getAll(),
);

/// 训练页「计划」分段 —— 周排期训练计划
class PlanSegment extends ConsumerWidget {
  const PlanSegment({super.key});

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_plansProvider);
    final theme = Theme.of(context);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
      data: (plans) {
        if (plans.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(26),
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child:
                      const Icon(Icons.calendar_month, size: 38, color: _orange),
                ),
                const SizedBox(height: 16),
                Text('还没有训练计划', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '把每周的训练排成计划，到点直接开练',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => context.push('/plan/create'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('创建计划'),
                ),
              ],
            ),
          );
        }

        final todayWeekday = DateTime.now().weekday % 7;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: plans.length,
          itemBuilder: (context, i) {
            final plan = plans[i];
            final todayItems = plan.days
                .where((d) => d.dayOfWeek == todayWeekday)
                .toList();
            final dayCount = plan.days.map((d) => d.dayOfWeek).toSet().length;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/plan/${plan.id}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _orange.withAlpha(30),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.calendar_month,
                                size: 16, color: _orange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  plan.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$dayCount 天训练 · ${plan.days.length} 个动作',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: theme.colorScheme.outline),
                                ),
                              ],
                            ),
                          ),
                          if (plan.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _orange.withAlpha(26),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '进行中',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: _orange),
                              ),
                            ),
                          const SizedBox(width: 2),
                          Icon(Icons.chevron_right,
                              size: 18, color: theme.colorScheme.outline),
                        ],
                      ),
                      if (todayItems.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.today, size: 13, color: _orange),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '今天安排 ${todayItems.length} 个动作',
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    color: _orange,
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context
                                  .push('/plan/${plan.id}/execute'),
                              style: TextButton.styleFrom(
                                foregroundColor: _orange,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                              child: const Text(
                                '开始',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
