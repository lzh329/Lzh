import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';

final _goalListProvider = FutureProvider<List<GoalEntity>>(
    (ref) => ref.watch(goalRepoProvider).getAll());

const _green = Color(0xFF66BB6A);
const _amber = Color(0xFFFFA726);
const _blue = Color(0xFF42A5F5);
const _purple = Color(0xFFAB47BC);

/// 目标管理页 —— v2 视觉统一
class GoalListPage extends ConsumerStatefulWidget {
  const GoalListPage({super.key});

  @override
  ConsumerState<GoalListPage> createState() => _GoalListPageState();
}

class _GoalListPageState extends ConsumerState<GoalListPage> {
  Color _colorFor(String type) => switch (type) {
        'weight' => _amber,
        'frequency' => _blue,
        _ => _purple,
      };

  IconData _iconFor(String type) => switch (type) {
        'weight' => Icons.flag,
        'frequency' => Icons.calendar_month,
        _ => Icons.star_outline,
      };

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(goalRepoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('目标管理')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _green,
        foregroundColor: Colors.black,
        onPressed: () => _showCreateDialog(context, repo),
        child: const Icon(Icons.add),
      ),
      body: ref.watch(_goalListProvider).when(
            loading: () => const ShimmerList(),
            error: (_, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('加载失败'),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.invalidate(_goalListProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (goals) {
              if (goals.isEmpty) {
                return _EmptyState(onCreate: () => _showCreateDialog(context, repo));
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 96),
                itemCount: goals.length,
                itemBuilder: (context, index) {
                  final goal = goals[index];
                  return _GoalCard(
                    goal: goal,
                    color: _colorFor(goal.type),
                    icon: _iconFor(goal.type),
                    onComplete: () async {
                      await repo.complete(goal.id);
                      if (mounted) setState(() {});
                    },
                    onDelete: () => _confirmDelete(context, repo, goal),
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

  Future<void> _confirmDelete(
      BuildContext context, dynamic repo, GoalEntity goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除目标'),
        content: const Text('确定要删除这个目标吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(goal.id);
    ref.invalidate(_goalListProvider);
  }
}

class _GoalCard extends StatelessWidget {
  final GoalEntity goal;
  final Color color;
  final IconData icon;
  final VoidCallback onComplete;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.color,
    required this.icon,
    required this.onComplete,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = goal.progressPercent;
    final typeLabel = GoalEntity.typeLabels[goal.type] ?? goal.type;
    final accent = goal.isCompleted ? _green : color;
    final unit = goal.type == 'weight' ? '斤' : '次';
    final digits = goal.type == 'weight' ? 1 : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(34),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    goal.isCompleted ? Icons.check_circle : icon,
                    size: 20,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabel,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: goal.isCompleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${goal.currentValue.toStringAsFixed(digits)} / ${goal.targetValue.toStringAsFixed(digits)} $unit',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pct.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, color: accent),
                    ),
                    Text('完成度',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline, fontSize: 10)),
                  ],
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.more_vert,
                      size: 20, color: theme.colorScheme.outline),
                  onSelected: (action) {
                    if (action == 'complete') onComplete();
                    if (action == 'delete') onDelete();
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
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100,
                minHeight: 6,
                backgroundColor: Colors.white.withAlpha(14),
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: _green.withAlpha(26),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.flag, size: 38, color: _green),
            ),
            const SizedBox(height: 18),
            Text('还没有目标', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '设定目标，让每一次努力都有方向',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.black87,
              ),
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('创建目标',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
