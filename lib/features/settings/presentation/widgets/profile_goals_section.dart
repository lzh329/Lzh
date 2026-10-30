import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/features/goal/domain/entities/goal_entity.dart';

import 'package:fittrack/core/theme/app_colors.dart';

const _green = AppColors.primary;
const _amber = AppColors.warning;
const _blue = AppColors.info;
const _purple = AppColors.analysis;

/// 目标管理页 —— v2 视觉统一
class ProfileGoalsSection extends ConsumerStatefulWidget {
  const ProfileGoalsSection({super.key});

  @override
  ConsumerState<ProfileGoalsSection> createState() =>
      _ProfileGoalsSectionState();
}

class _ProfileGoalsSectionState extends ConsumerState<ProfileGoalsSection> {
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

    // 新建入口从原页面的右下角 FAB 改成区块标题右侧的「＋ 新建」：
    // 新页不挂全局 FAB（那是整页级动作，不该只服务目标），
    // 标题 + 右侧操作按钮的结构与训练页「我的模板」区保持一致。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // 左侧标题由外层「个人档案」页给，这里只留右侧操作
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showCreateDialog(context, repo),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.primaryText,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        Expanded(
          child: ref.watch(goalListProvider).when(
                loading: () => const ShimmerList(),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('加载失败'),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(goalListProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
                data: (goals) {
                  if (goals.isEmpty) {
                    return _EmptyState(
                        onCreate: () => _showCreateDialog(context, repo));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
        ),
      ],
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
                  ButtonSegment(
                      value: 'weight',
                      label: Text('体重', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: 'frequency',
                      label: Text('频率', style: TextStyle(fontSize: 12))),
                  ButtonSegment(
                      value: 'custom',
                      label: Text('自定义', style: TextStyle(fontSize: 12))),
                ],
                selected: {type},
                onSelectionChanged: (v) => setDlgState(() => type = v.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '目标值',
                  hintText: type == 'weight' ? '例如: 120（斤）' : '例如: 20（次/周）',
                  suffixText: type == 'weight' ? '斤' : '次',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final v = double.tryParse(targetCtrl.text);
                if (v != null && v > 0) {
                  await repo.create(
                      type: type, targetValue: v, startDate: DateTime.now());
                  if (ctx.mounted) Navigator.pop(ctx);
                  ref.invalidate(goalListProvider);
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(goal.id);
    ref.invalidate(goalListProvider);
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
                          decoration: goal.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${goal.currentValue.toStringAsFixed(digits)} / ${goal.targetValue.toStringAsFixed(digits)} $unit',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: accent),
                    ),
                    Text('完成度',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary, fontSize: 10)),
                  ],
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.more_vert,
                      size: 20, color: AppColors.textTertiary),
                  onSelected: (action) {
                    if (action == 'complete') onComplete();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    if (!goal.isCompleted)
                      const PopupMenuItem(
                          value: 'complete', child: Text('标记完成')),
                    const PopupMenuItem(
                      value: 'delete',
                      child:
                          Text('删除', style: TextStyle(color: AppColors.danger)),
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
                backgroundColor: AppColors.surfaceMuted,
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
    // 空态只留一行轻文案：新建入口在区块标题行右侧（「＋ 新建」），
    // 这里再放一个大按钮是重复入口，而且空态本身不该抢走半屏注意力。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
      child: Text(
        '还没有目标，点右上角「＋ 新建」添加',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    );
  }
}
