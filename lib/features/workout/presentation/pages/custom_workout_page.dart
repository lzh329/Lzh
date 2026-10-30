import 'package:flutter/material.dart';

export 'package:fittrack/features/workout/presentation/widgets/selected_exercise.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/presentation/widgets/exercise_item_editor.dart';
import 'package:fittrack/features/workout/presentation/widgets/exercise_category_chip.dart';
import 'package:fittrack/features/workout/presentation/widgets/selected_exercise.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

import 'package:fittrack/core/theme/app_colors.dart';

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
          _selected.add(SelectedExercise(
            exercise: ex,
            targetSets: setsForEx.clamp(1, 10),
            targetReps: ex.category == 'cardio' ? null : ex.defaultReps,
            targetDurationSec: ex.defaultDurationSec,
          ));
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
                setState(() {
                  _selected.clear();
                  _copiedLast = false;
                });
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
                    children: _selected
                        .map((se) => Chip(
                              avatar: CircleAvatar(
                                backgroundColor: (AppTheme.categoryColors[
                                            se.exercise.category] ??
                                        AppColors.textTertiary)
                                    .withAlpha(40),
                                child: Icon(
                                    AppTheme
                                        .categoryIcons[se.exercise.category],
                                    size: 14,
                                    color: AppTheme
                                        .categoryColors[se.exercise.category]),
                              ),
                              label: Text('${se.exercise.name} ${se.detail}',
                                  style: const TextStyle(fontSize: 12)),
                              deleteIcon: const Icon(Icons.close, size: 16),
                              onDeleted: () =>
                                  setState(() => _selected.remove(se)),
                            ))
                        .toList(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: '搜索动作...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true),
                  onChanged: (v) => setState(() {
                    _searchQuery = v;
                    _cachedFuture = null;
                  }),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    ExerciseCategoryChip(
                        label: '全部',
                        value: 'all',
                        selected: _selectedCategory,
                        onTap: (v) => setState(() {
                              _selectedCategory = v;
                              _cachedFuture = null;
                            })),
                    ...AppTheme.categoryLabels.entries.map(
                      (e) => ExerciseCategoryChip(
                          label: e.value,
                          value: e.key,
                          selected: _selectedCategory,
                          onTap: (v) => setState(() {
                                _selectedCategory = v;
                                _cachedFuture = null;
                              })),
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
                        final isSelected =
                            _selected.any((s) => s.exercise.id == ex.id);
                        final catColor = AppTheme.categoryColors[ex.category] ??
                            AppColors.textTertiary;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: catColor.withAlpha(40),
                            child: Icon(
                                AppTheme.categoryIcons[ex.category] ??
                                    Icons.fitness_center,
                                color: catColor,
                                size: 20),
                          ),
                          title: Text(ex.name),
                          subtitle: Text(
                            '${AppTheme.categoryLabels[ex.category] ?? ex.category}${ex.muscleGroup != null ? ' · ${ex.muscleGroup}' : ''}',
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing: isSelected
                              ? IconButton(
                                  icon: const Icon(Icons.check_circle,
                                      color: AppColors.success),
                                  onPressed: () => setState(() =>
                                      _selected.removeWhere(
                                          (s) => s.exercise.id == ex.id)),
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
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  elevation: 6,
                  icon: const Icon(Icons.play_arrow, size: 24),
                  label: Text('开始训练 (${_selected.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
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

  /// 添加动作：计量方式由**动作自己的分类**决定（复用模板编辑那套判定）
  ///
  /// 之前这里只有"组数"一个输入，力量动作记不了次数、有氧记不了时长，
  /// 用户说的"没区分有氧按时间"就是这个。
  Future<void> _addExercise(
      BuildContext context, ExerciseEntity exercise) async {
    final seed = EditItem(
      exerciseId: exercise.id,
      name: exercise.name,
      category: exercise.category,
      sets: 3,
      reps: exercise.category == 'cardio' ? null : (exercise.defaultReps ?? 12),
      durationSec: exercise.defaultDurationSec,
    );
    final result = await showExerciseItemEditor(context, item: seed);
    if (result == null || !mounted) return;
    setState(() => _selected.add(SelectedExercise(
          exercise: exercise,
          targetSets: result.sets,
          targetReps: result.reps,
          targetDurationSec: result.durationSec,
        )));
  }

  void _startWorkout(BuildContext context) {
    final slots = _selected
        .map((se) => ExerciseSlot(
              exerciseId: se.exercise.id,
              exerciseName: se.exercise.name,
              category: se.exercise.category,
              targetSets: se.targetSets,
              // 用户填的值优先，没填才退回动作默认值
              targetReps: se.targetReps ?? se.exercise.defaultReps,
              targetWeightKg: se.exercise.defaultWeightKg,
              targetDurationSec:
                  se.targetDurationSec ?? se.exercise.defaultDurationSec,
            ))
        .toList();
    context.pushReplacement('/workout/active', extra: slots);
  }
}
