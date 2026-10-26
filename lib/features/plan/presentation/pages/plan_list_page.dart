import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';

import 'package:fittrack/core/theme/app_colors.dart';

final _planListProvider = FutureProvider<List<PlanEntity>>(
    (ref) => ref.watch(planRepoProvider).getAll());

const _green = AppColors.primary;
const _grey = AppColors.textTertiary;

class PlanListPage extends ConsumerStatefulWidget {
  const PlanListPage({super.key});

  @override
  ConsumerState<PlanListPage> createState() => _PlanListPageState();
}

class _PlanListPageState extends ConsumerState<PlanListPage> {
  bool _selectMode = false;
  final Set<int> _selectedIds = {};

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<PlanEntity> plans) {
    setState(() {
      if (_selectedIds.length == plans.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(plans.map((p) => p.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(planRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length} 项' : '训练计划'),
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close), onPressed: _toggleSelectMode)
            : null,
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: () => _toggleSelectAll((_cachedPlans)),
              child: Text(
                  _selectedIds.length == _cachedPlans.length ? '反选' : '全选'),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: _selectedIds.isEmpty
                      ? AppColors.textTertiary
                      : AppColors.danger),
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => _confirmBatchDelete(context, repo),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectMode,
              tooltip: '批量管理',
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () async {
                await context.push('/plan/create');
                if (mounted) setState(() {});
              },
            ),
          ],
        ],
      ),
      body: ref.watch(_planListProvider).when(
            loading: () => const ShimmerList(),
            error: (_, __) => const Center(child: Text('加载失败')),
            data: (plans) {
              _cachedPlans = plans;

              if (plans.isEmpty) {
                return Center(
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
                        child: const Icon(Icons.calendar_month,
                            size: 38, color: _green),
                      ),
                      const SizedBox(height: 18),
                      Text('还没有训练计划', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        '创建计划，让每次训练都有章可循',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: AppColors.onPrimary,
                        ),
                        onPressed: () async {
                          await context.push('/plan/create');
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('创建计划',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: plans.length,
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  final dayCount =
                      plan.days.map((d) => d.dayOfWeek).toSet().length;
                  final isSelected = _selectedIds.contains(plan.id);
                  final activeColor = plan.isActive ? _green : _grey;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 2),
                      leading: _selectMode
                          ? Checkbox(
                              value: isSelected,
                              onChanged: (_) {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(plan.id);
                                  } else {
                                    _selectedIds.add(plan.id);
                                  }
                                });
                              },
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: activeColor.withAlpha(30),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                plan.isActive
                                    ? Icons.calendar_month
                                    : Icons.calendar_today,
                                size: 20,
                                color: activeColor,
                              ),
                            ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: theme.textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (plan.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _green.withAlpha(26),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '进行中',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: _green),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '$dayCount 天训练 · ${plan.days.length} 个动作',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                      trailing: _selectMode
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  await context.push('/plan/create',
                                      extra: plan);
                                  if (mounted) setState(() {});
                                } else if (action == 'start') {
                                  if (!mounted) return;
                                  context.push('/plan/${plan.id}/execute');
                                } else if (action == 'toggle') {
                                  await repo.toggleActive(
                                      plan.id, !plan.isActive);
                                  if (mounted) setState(() {});
                                } else if (action == 'delete') {
                                  if (!mounted) return;
                                  _confirmDelete(context, repo, plan);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'start', child: Text('开始训练')),
                                const PopupMenuItem(
                                    value: 'edit', child: Text('编辑')),
                                const PopupMenuItem(
                                  value: 'toggle',
                                  child: Text('启用/停用'),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除',
                                      style:
                                          TextStyle(color: AppColors.danger)),
                                ),
                              ],
                            ),
                      onTap: _selectMode
                          ? () {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(plan.id);
                                } else {
                                  _selectedIds.add(plan.id);
                                }
                              });
                            }
                          : () => context.push('/plan/${plan.id}'),
                    ),
                  );
                },
              );
            },
          ),
    );
  }

  List<PlanEntity> _cachedPlans = [];

  void _confirmDelete(
      BuildContext context, PlanRepository repo, PlanEntity plan) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除计划'),
        content: Text('确定要删除「${plan.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
            onPressed: () async {
              await repo.delete(plan.id);
              _selectedIds.remove(plan.id);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _confirmBatchDelete(BuildContext context, PlanRepository repo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除计划'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 个计划吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
            onPressed: () async {
              for (final id in _selectedIds.toList()) {
                await repo.delete(id);
              }
              _selectedIds.clear();
              _selectMode = false;
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
  }
}
