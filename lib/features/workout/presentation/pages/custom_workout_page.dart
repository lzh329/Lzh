import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

class CustomWorkoutPage extends ConsumerStatefulWidget {
  const CustomWorkoutPage({super.key});

  @override
  ConsumerState<CustomWorkoutPage> createState() => _CustomWorkoutPageState();
}

class _CustomWorkoutPageState extends ConsumerState<CustomWorkoutPage> {
  final List<SelectedExercise> _selected = [];
  String _searchQuery = '';
  String _selectedCategory = 'all';
  Future<List<ExerciseEntity>>? _cachedFuture;
  bool _copiedLast = false;

  @override
  void initState() {
    super.initState();
    _tryCopyLastWorkout();
  }

  Future<void> _tryCopyLastWorkout() async {
    if (_copiedLast || _selected.isNotEmpty) return;
    final allWorkouts = await ref.read(workoutRepoProvider).getAll();
    if (allWorkouts.isEmpty) return;

    final last = allWorkouts.last;
    final exerciseIds = last.sets.map((s) => s.exerciseId).toSet();
    final exercises = await ref.read(exerciseRepoProvider).getAll();
    final exMap = {for (final e in exercises) e.id: e};

    if (!mounted) return;
    setState(() {
      for (final id in exerciseIds) {
        final ex = exMap[id];
        if (ex != null) {
          final setsForEx = last.sets.where((s) => s.exerciseId == id).length;
          _selected.add(SelectedExercise(exercise: ex, targetSets: setsForEx.clamp(1, 10)));
        }
      }
      _copiedLast = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(exerciseRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义训练'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() { _selected.clear(); _copiedLast = false; });
                _tryCopyLastWorkout();
              },
              child: const Text('重新复制', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
        children: [
          if (_selected.isNotEmpty)
            Container(
              width: double.infinity,
              color: theme.colorScheme.primaryContainer.withAlpha(50),
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _selected.map((se) => Chip(
                  avatar: CircleAvatar(
                    backgroundColor: (AppTheme.categoryColors[se.exercise.category] ?? Colors.grey).withAlpha(40),
                    child: Icon(AppTheme.categoryIcons[se.exercise.category], size: 14,
                      color: AppTheme.categoryColors[se.exercise.category]),
                  ),
                  label: Text('${se.exercise.name} × ${se.targetSets}组', style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => setState(() => _selected.remove(se)),
                )).toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(hintText: '搜索动作...', prefixIcon: Icon(Icons.search), isDense: true),
              onChanged: (v) => setState(() { _searchQuery = v; _cachedFuture = null; }),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _CatChip(label: '全部', value: 'all', selected: _selectedCategory, onTap: (v) => setState(() { _selectedCategory = v; _cachedFuture = null; })),
                ...AppTheme.categoryLabels.entries.map((e) =>
                  _CatChip(label: e.value, value: e.key, selected: _selectedCategory, onTap: (v) => setState(() { _selectedCategory = v; _cachedFuture = null; })),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<ExerciseEntity>>(
              future: _cachedFuture ??= _getExercises(repo),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final exercises = snapshot.data ?? [];
                if (exercises.isEmpty) {
                  return const Center(child: Text('暂无匹配的动作'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final ex = exercises[index];
                    final isSelected = _selected.any((s) => s.exercise.id == ex.id);
                    final catColor = AppTheme.categoryColors[ex.category] ?? Colors.grey;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: catColor.withAlpha(40),
                        child: Icon(AppTheme.categoryIcons[ex.category] ?? Icons.fitness_center, color: catColor, size: 20),
                      ),
                      title: Text(ex.name),
                      subtitle: Text(
                        '${AppTheme.categoryLabels[ex.category] ?? ex.category}${ex.muscleGroup != null ? ' · ${ex.muscleGroup}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: isSelected
                        ? IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: () => setState(() => _selected.removeWhere((s) => s.exercise.id == ex.id)),
                          )
                        : const Icon(Icons.add_circle_outline),
                      onTap: () => _addExercise(context, ex),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      // 浮动开始按钮（屏幕 2/3 处）
      if (_selected.isNotEmpty)
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).size.height / 5,
          child: Center(
            child: FloatingActionButton.extended(
              onPressed: () => _startWorkout(context),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              elevation: 6,
              icon: const Icon(Icons.play_arrow, size: 24),
              label: Text('开始训练 (${_selected.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
          ],
        ),
    );
  }

  Future<List<ExerciseEntity>> _getExercises(ExerciseRepository repo) async {
    if (_searchQuery.isNotEmpty) return repo.search(_searchQuery);
    if (_selectedCategory == 'all') return repo.getAll();
    return repo.getByCategory(_selectedCategory);
  }

  void _addExercise(BuildContext context, ExerciseEntity exercise) {
    showDialog(
      context: context,
      builder: (ctx) {
        int sets = 3;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(exercise.name),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('目标组数'),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: sets > 1 ? () => setDialogState(() => sets--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$sets', style: Theme.of(context).textTheme.headlineMedium),
                    IconButton(
                      onPressed: sets < 10 ? () => setDialogState(() => sets++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  setState(() => _selected.add(SelectedExercise(exercise: exercise, targetSets: sets)));
                  Navigator.pop(ctx);
                },
                child: const Text('添加'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _startWorkout(BuildContext context) {
    final slots = _selected
        .map((se) => ExerciseSlot(
              exerciseId: se.exercise.id,
              exerciseName: se.exercise.name,
              category: se.exercise.category,
              targetSets: se.targetSets,
              targetReps: se.exercise.defaultReps,
              targetWeightKg: se.exercise.defaultWeightKg,
              targetDurationSec: se.exercise.defaultDurationSec,
            ))
        .toList();
    context.pushReplacement('/workout/active', extra: slots);
  }
}

class SelectedExercise {
  final ExerciseEntity exercise;
  final int targetSets;
  const SelectedExercise({required this.exercise, required this.targetSets});
}

class _CatChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  const _CatChip({required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: value == selected,
        onSelected: (_) => onTap(value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
