import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

/// "最近训练"区块 —— 主控页底部
class RecentWorkoutsSection extends StatelessWidget {
  final List<WorkoutEntity> workouts;
  final Map<int, String> exerciseNames;

  const RecentWorkoutsSection({
    super.key,
    required this.workouts,
    required this.exerciseNames,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 6),
          child: Text('最近训练', style: theme.textTheme.titleMedium),
        ),
        if (workouts.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.fitness_center,
                        size: 36, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      '还没有训练记录\n点击右上角开始训练',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          ...workouts.take(3).map((w) => _WorkoutTile(
                workout: w,
                exerciseNames: exerciseNames,
              )),
      ],
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  final WorkoutEntity workout;
  final Map<int, String> exerciseNames;

  const _WorkoutTile({required this.workout, required this.exerciseNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final names = workout.sets
        .map((s) => exerciseNames[s.exerciseId] ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .take(3)
        .join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/workout/${workout.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF66BB6A).withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center,
                    size: 18, color: Color(0xFF66BB6A)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names.isEmpty ? '训练' : names,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workout.date.month}月${workout.date.day}日 · ${workout.sets.length} 组',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
