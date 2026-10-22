import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

final _historyProvider = FutureProvider<List<WorkoutEntity>>(
  (ref) => ref.watch(workoutRepoProvider).getAll(),
);

/// 训练页「历史」分段 —— 最近训练记录
class HistorySegment extends ConsumerWidget {
  const HistorySegment({super.key});

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_historyProvider);
    final theme = Theme.of(context);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
      data: (workouts) {
        if (workouts.isEmpty) {
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
                  child: const Icon(Icons.history, size: 38, color: _orange),
                ),
                const SizedBox(height: 16),
                Text('还没有训练记录', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '完成第一次训练后，记录会出现在这里',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: workouts.length,
          itemBuilder: (context, i) {
            final w = workouts[i];
            final minutes =
                w.durationSec != null ? (w.durationSec! / 60).round() : null;
            final subtitle = '${w.completedSets}/${w.totalSets} 组'
                '${minutes != null ? ' · $minutes 分钟' : ''}';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.fitness_center,
                      size: 17, color: _orange),
                ),
                title: Text(
                  DateFormat('M月d日 HH:mm').format(w.date),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  subtitle,
                  style: TextStyle(
                      fontSize: 10.5, color: theme.colorScheme.outline),
                ),
                trailing: Icon(Icons.chevron_right,
                    size: 16, color: theme.colorScheme.outline),
                onTap: () => context.push('/workout/${w.id}'),
              ),
            );
          },
        );
      },
    );
  }
}
