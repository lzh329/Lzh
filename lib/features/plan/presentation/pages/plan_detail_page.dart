import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';

const _green = Color(0xFFFF8A00);

class PlanDetailPage extends ConsumerWidget {
  final int planId;
  const PlanDetailPage({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(planRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('计划详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final plan = await repo.getById(planId);
              if (plan != null && context.mounted) {
                context.push('/plan/create', extra: plan);
              }
            },
          ),
          TextButton.icon(
            onPressed: () => context.push('/plan/$planId/execute'),
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('开始'),
          ),
        ],
      ),
      body: FutureBuilder<PlanEntity?>(
        future: repo.getById(planId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final plan = snapshot.data;
          if (plan == null) {
            return const Center(child: Text('计划不存在'));
          }

          final groupedByDay = <int, List<PlanDayEntity>>{};
          for (final day in plan.days) {
            groupedByDay.putIfAbsent(day.dayOfWeek, () => []).add(day);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _green.withAlpha(32),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.calendar_month,
                                size: 18, color: _green),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              plan.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${plan.days.map((d) => d.dayOfWeek).toSet().length} 天',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _green),
                          ),
                        ],
                      ),
                      if (plan.note != null && plan.note!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          plan.note!,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white54, height: 1.5),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '共 ${plan.days.length} 个动作',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ...PlanDayEntity.dayLabels.asMap().entries.map((entry) {
                final day = entry.key;
                final label = entry.value;
                final exercises = groupedByDay[day] ?? [];

                if (exercises.isEmpty) return const SizedBox.shrink();

                final isToday = DateTime.now().weekday % 7 == day;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: isToday ? _green.withAlpha(14) : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isToday) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _green,
                                ),
                              ),
                              const SizedBox(width: 7),
                            ],
                            Text(
                              label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isToday ? _green : null,
                              ),
                            ),
                            if (isToday)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Text(
                                  '今天',
                                  style:
                                      TextStyle(fontSize: 10, color: _green),
                                ),
                              ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: () => context.push(
                                  '/plan/$planId/execute', extra: day),
                              icon: const Icon(Icons.play_arrow, size: 16),
                              label: const Text('开始',
                                  style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: _green,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...exercises.map((de) => FutureBuilder<ExerciseEntity?>(
                          future: ref.read(exerciseRepoProvider).getById(de.exerciseId),
                          builder: (context, snap) {
                            final ex = snap.data;
                            final catColor =
                                AppTheme.categoryColors[ex?.category] ?? Colors.grey;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: catColor.withAlpha(26),
                                    ),
                                    child: Icon(
                                      AppTheme.categoryIcons[ex?.category] ??
                                          Icons.fitness_center,
                                      size: 16,
                                      color: catColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(ex?.name ?? '动作 #${de.exerciseId}',
                                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                        Text(_formatTarget(de),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: theme.colorScheme.outline, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  Text('休息 ${de.restSec}s',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline, fontSize: 10)),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            );
                          },
                        )),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  String _formatTarget(PlanDayEntity de) {
    final parts = <String>[];
    parts.add('${de.targetSets} 组');
    if (de.targetReps != null) parts.add('${de.targetReps} 次');
    if (de.targetWeightKg != null) parts.add('${de.targetWeightKg!.toStringAsFixed(1)} kg');
    if (de.targetDurationSec != null) {
      final m = de.targetDurationSec! ~/ 60;
      final s = de.targetDurationSec! % 60;
      parts.add(m > 0 ? '$m 分 $s 秒' : '$s 秒');
    }
    return parts.join(' · ');
  }
}
