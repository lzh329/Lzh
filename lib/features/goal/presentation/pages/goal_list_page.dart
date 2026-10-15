import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';

final _goalListProvider = FutureProvider<List<GoalEntity>>((ref) => ref.watch(goalRepoProvider).getAll());

class GoalListPage extends ConsumerStatefulWidget {
  const GoalListPage({super.key});

  @override
  ConsumerState<GoalListPage> createState() => _GoalListPageState();
}

class _GoalListPageState extends ConsumerState<GoalListPage> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(goalRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('目标管理')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDialog(context, repo),
        child: const Icon(Icons.add),
      ),
      body: ref.watch(_goalListProvider).when(
        loading: () => const ShimmerList(),
        error: (_, __) => const Center(child: Text('加载失败')),
        data: (goals) {

          if (goals.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.flag, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('还没有目标', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => _showCreateDialog(context, repo),
                    icon: const Icon(Icons.add),
                    label: const Text('创建目标'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            itemCount: goals.length,
            itemBuilder: (context, index) {
              final goal = goals[index];
              final pct = goal.progressPercent;
              final typeLabel = GoalEntity.typeLabels[goal.type] ?? goal.type;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            goal.isCompleted ? Icons.check_circle : Icons.flag,
                            color: goal.isCompleted ? Colors.green : theme.colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(typeLabel,
                              style: theme.textTheme.titleSmall?.copyWith(
                                decoration: goal.isCompleted ? TextDecoration.lineThrough : null,
                              )),
                          ),
                          Text(
                            '${goal.currentValue.toStringAsFixed(goal.type == 'weight' ? 1 : 0)} / ${goal.targetValue.toStringAsFixed(goal.type == 'weight' ? 1 : 0)}${goal.type == 'weight' ? ' 斤' : ' 次'}',
                            style: theme.textTheme.bodySmall,
                          ),
                          PopupMenuButton<String>(
                            onSelected: (action) {
                              if (action == 'complete') repo.complete(goal.id);
                              if (action == 'delete') _confirmDelete(context, repo, goal);
                              setState(() {});
                            },
                            itemBuilder: (_) => [
                              if (!goal.isCompleted)
                                const PopupMenuItem(value: 'complete', child: Text('标记完成')),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct / 100,
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: goal.isCompleted ? Colors.green : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${pct.toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context, dynamic repo) {
    String type = 'weight';
    final targetCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('创建目标'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'weight', label: Text('体重', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'frequency', label: Text('频率', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'custom', label: Text('自定义', style: TextStyle(fontSize: 12))),
                ],
                selected: {type},
                onSelectionChanged: (v) => setDlgState(() => type = v.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '目标值',
                  hintText: type == 'weight' ? '例如: 120（斤）' : '例如: 20（次/周）',
                  suffixText: type == 'weight' ? '斤' : '次',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final v = double.tryParse(targetCtrl.text);
                if (v != null && v > 0) {
                  await repo.create(type: type, targetValue: v, startDate: DateTime.now());
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(_goalListProvider);
                }
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, dynamic repo, GoalEntity goal) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除目标'),
        content: const Text('确定要删除这个目标吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await repo.delete(goal.id);
              if (ctx.mounted) Navigator.pop(ctx);
              ref.invalidate(_goalListProvider);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
