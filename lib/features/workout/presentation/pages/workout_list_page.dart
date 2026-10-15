import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

class WorkoutListPage extends ConsumerStatefulWidget {
  const WorkoutListPage({super.key});

  @override
  ConsumerState<WorkoutListPage> createState() => _WorkoutListPageState();
}

class _WorkoutListPageState extends ConsumerState<WorkoutListPage> {
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _selectMode = false;
  final Set<int> _selectedIds = {};
  List<WorkoutEntity> _cachedWorkouts = [];
  Map<int, String> _exerciseNames = {};

  @override
  void initState() {
    super.initState();
    _loadExerciseNames();
  }

  void _loadExerciseNames() async {
    final exercises = await ref.read(exerciseRepoProvider).getAll();
    setState(() {
      _exerciseNames = {for (final e in exercises) e.id: e.name};
    });
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  String _subtitle(WorkoutEntity w) {
    final date = DateFormat('yyyy年MM月dd日 HH:mm').format(w.date);
    if (w.durationSec != null) {
      final m = w.durationSec! ~/ 60;
      final s = w.durationSec! % 60;
      return '$date · ${m}分${s}秒';
    }
    return date;
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _cachedWorkouts.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_cachedWorkouts.map((w) => w.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(workoutRepoProvider);
    ref.watch(dashboardRefreshCount);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length} 项' : '训练记录'),
        leading: _selectMode
          ? IconButton(icon: const Icon(Icons.close), onPressed: _toggleSelectMode)
          : null,
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(_selectedIds.length == _cachedWorkouts.length ? '反选' : '全选'),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                color: _selectedIds.isEmpty ? theme.colorScheme.outline : Colors.red),
              onPressed: _selectedIds.isEmpty ? null : () => _confirmBatchDelete(context, repo),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: () => context.push('/plan'),
              tooltip: '训练计划',
            ),
            IconButton(
              icon: const Icon(Icons.bar_chart),
              onPressed: () => context.push('/workout/stats'),
              tooltip: '训练统计',
            ),
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectMode,
              tooltip: '批量管理',
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showDateFilter(context),
            ),
          ],
        ],
      ),
      body: FutureBuilder<List<WorkoutEntity>>(
        future: repo.getAll(from: _fromDate, to: _toDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ShimmerList();
          }
          var workouts = snapshot.data ?? [];
          _cachedWorkouts = workouts;

          if (workouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sports_gymnastics, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('暂无训练记录', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => context.push('/workout/quick-start'),
                    icon: const Icon(Icons.add),
                    label: const Text('开始训练'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: workouts.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final w = workouts[index];
              final exerciseIds = w.sets.map((s) => s.exerciseId).toSet();
              final names = exerciseIds
                  .map((id) => _exerciseNames[id] ?? '')
                  .where((n) => n.isNotEmpty)
                  .toList();
              final exerciseLabel = names.isNotEmpty
                  ? '${names.join('、')}  · ${w.totalSets} 组'
                  : '${exerciseIds.length} 个动作 · ${w.totalSets} 组';
              final isSelected = _selectedIds.contains(w.id);

              final tile = ListTile(
                leading: _selectMode
                  ? Checkbox(
                      value: isSelected,
                      onChanged: (_) {
                        setState(() {
                          if (isSelected) _selectedIds.remove(w.id);
                          else _selectedIds.add(w.id);
                        });
                      },
                    )
                  : CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(Icons.fitness_center, color: theme.colorScheme.onPrimaryContainer, size: 20),
                    ),
                title: Text(exerciseLabel),
                subtitle: Text(_subtitle(w)),
                trailing: _selectMode ? null : const Icon(Icons.chevron_right),
                onTap: _selectMode
                  ? () {
                      setState(() {
                        if (isSelected) _selectedIds.remove(w.id);
                        else _selectedIds.add(w.id);
                      });
                    }
                  : () => context.push('/workout/${w.id}'),
              );

              // 非选择模式下，允许滑动单独删除
              if (_selectMode) return tile;
              return Dismissible(
                key: Key('workout-${w.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  return await _confirmSingleDelete(context, repo, w.id);
                },
                onDismissed: (_) {
                  ref.read(dashboardRefreshCount.notifier).state++;
                  setState(() {});
                },
                child: tile,
              );
            },
          );
        },
      ),
      floatingActionButton: _selectMode
        ? null
        : FloatingActionButton(
            onPressed: () => context.push('/workout/quick-start'),
            child: const Icon(Icons.add),
          ),
    );
  }

  Future<bool> _confirmSingleDelete(BuildContext context, WorkoutRepository repo, int id) async {
    bool confirmed = false;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除训练记录'),
        content: const Text('确定要删除这条训练记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await repo.delete(id);
              confirmed = true;
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed;
  }

  void _confirmBatchDelete(BuildContext context, WorkoutRepository repo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除训练记录'),
        content: Text('确定要删除选中的 ${_selectedIds.length} 条训练记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              for (final id in _selectedIds.toList()) {
                await repo.delete(id);
              }
              _selectedIds.clear();
              _selectMode = false;
              ref.read(dashboardRefreshCount.notifier).state++;
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('全部删除'),
          ),
        ],
      ),
    );
  }

  void _showDateFilter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('按日期筛选', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: _fromDate ?? DateTime.now().subtract(const Duration(days: 30)),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) _fromDate = date;
                    },
                    child: Text(_fromDate != null ? DateFormat('yyyy/MM/dd').format(_fromDate!) : '开始日期'),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('至')),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        initialDate: _toDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) _toDate = date;
                    },
                    child: Text(_toDate != null ? DateFormat('yyyy/MM/dd').format(_toDate!) : '结束日期'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() { _fromDate = null; _toDate = null; });
                    Navigator.pop(ctx);
                  },
                  child: const Text('清除筛选'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    setState(() {});
                    Navigator.pop(ctx);
                  },
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
