import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/plan/domain/entities/plan_entity.dart';
import 'package:fittrack/features/plan/domain/entities/plan_day_entity.dart';
import 'package:fittrack/features/plan/domain/repositories/plan_repository.dart';

const _green = Color(0xFFFF8A00);
const _blue = Color(0xFF38BDF8);

class PlanCreatePage extends ConsumerStatefulWidget {
  const PlanCreatePage({super.key});

  @override
  ConsumerState<PlanCreatePage> createState() => _PlanCreatePageState();
}

class _PlanCreatePageState extends ConsumerState<PlanCreatePage> {
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  // dayOfWeek → list of (exerciseId, targetSets, targetReps, targetWeight, restSec)
  final Map<int, List<_DayExercise>> _schedule = {
    1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 0: [],
  };

  int _selectedDay = DateTime.now().weekday % 7;
  bool _isEditing = false;
  int? _editingPlanId;
  final Map<int, String> _exerciseNameCache = {};
  bool _namesLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = GoRouterState.of(context).extra;
    if (args is PlanEntity && !_isEditing) {
      _isEditing = true;
      _editingPlanId = args.id;
      _nameCtrl.text = args.name;
      _noteCtrl.text = args.note ?? '';
      for (final day in args.days) {
        _schedule[day.dayOfWeek]?.add(_DayExercise(
          exerciseId: day.exerciseId,
          targetSets: day.targetSets,
          targetReps: day.targetReps,
          targetWeightKg: day.targetWeightKg,
          targetDurationSec: day.targetDurationSec,
          restSec: day.restSec,
        ));
      }
    }
    if (!_namesLoaded) {
      _namesLoaded = true;
      ref.read(exerciseRepoProvider).getAll().then((exercises) {
        if (!mounted) return;
        setState(() {
          for (final e in exercises) {
            _exerciseNameCache[e.id] = e.name;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayActions = _schedule[_selectedDay] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑计划' : '创建计划'),
        actions: [
          TextButton(
            onPressed: () => _save(),
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── 基本信息 ──
          _groupCard(
            theme,
            icon: Icons.edit_note,
            color: _green,
            title: '基本信息',
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '计划名称',
                  hintText: '例如: 三分化训练',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── 排期 ──
          _groupCard(
            theme,
            icon: Icons.calendar_month,
            color: _blue,
            title: '排期',
            children: [
              Row(
                children: [
                  for (final entry in PlanDayEntity.dayLabels.asMap().entries)
                    Expanded(
                      child: Builder(
                        builder: (_) {
                          final isSelected = entry.key == _selectedDay;
                          final count = (_schedule[entry.key] ?? []).length;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedDay = entry.key),
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _green.withAlpha(26)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? _green
                                      : Colors.white.withAlpha(16),
                                  width: isSelected ? 1.4 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected
                                          ? _green
                                          : Colors.white54,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: count > 0
                                          ? Colors.white
                                          : Colors.white30,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (todayActions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      '${PlanDayEntity.dayLabels[_selectedDay]}还没有动作，点击下方添加',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                )
              else
                ...todayActions.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final de = entry.value;
                  final label = _exerciseNameCache[de.exerciseId] ??
                      '动作 #${de.exerciseId}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _green,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(label,
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('× ${de.targetSets} 组',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontSize: 11)),
                        const SizedBox(width: 2),
                        IconButton(
                          icon: const Icon(Icons.tune, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: '调整组数',
                          onPressed: () =>
                              _editDayExercise(context, de, idx),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                          tooltip: '移除',
                          onPressed: () {
                            setState(() => _schedule[_selectedDay]?.removeAt(idx));
                          },
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 10),
              SizedBox(
                height: 42,
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showExercisePicker(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('给${PlanDayEntity.dayLabels[_selectedDay]}添加动作'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: BorderSide(color: _green.withAlpha(80)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.black87,
              ),
              onPressed: () => _save(),
              child: Text(
                _isEditing ? '保存修改' : '创建计划',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(
    ThemeData theme, {
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  void _showExercisePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ExercisePickerSheet(
        onSelect: (exercise) {
          setState(() {
            _schedule[_selectedDay]?.add(_DayExercise(
              exerciseId: exercise.id,
              targetSets: 3,
            ));
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _editDayExercise(BuildContext context, _DayExercise de, int index) {
    int sets = de.targetSets;
    final repsCtrl = TextEditingController(text: de.targetReps?.toString() ?? '');
    final weightCtrl = TextEditingController(text: de.targetWeightKg?.toString() ?? '');
    final durationCtrl = TextEditingController(text: de.targetDurationSec?.toString() ?? '');
    int rest = de.restSec;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑训练参数'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('目标组数：'),
                    IconButton(
                      onPressed: sets > 1 ? () => setDialogState(() => sets--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$sets', style: Theme.of(context).textTheme.headlineSmall),
                    IconButton(
                      onPressed: sets < 10 ? () => setDialogState(() => sets++) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '目标次数（可选）', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: '目标重量 kg（可选）', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '目标时长 秒（可选）', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('组间休息：'),
                    IconButton(
                      onPressed: rest > 15 ? () => setDialogState(() => rest -= 15) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${rest}s'),
                    IconButton(
                      onPressed: rest < 300 ? () => setDialogState(() => rest += 15) : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                setState(() {
                  _schedule[_selectedDay]?[index] = _DayExercise(
                    exerciseId: de.exerciseId,
                    targetSets: sets,
                    targetReps: int.tryParse(repsCtrl.text),
                    targetWeightKg: double.tryParse(weightCtrl.text),
                    targetDurationSec: int.tryParse(durationCtrl.text),
                    restSec: rest,
                  );
                });
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入计划名称')),
      );
      return;
    }

    final repo = ref.read(planRepoProvider);

    try {
      if (_isEditing && _editingPlanId != null) {
        await repo.updateName(_editingPlanId!, name, note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());

        final days = <PlanDayInput>[];
        for (final entry in _schedule.entries) {
          for (final de in entry.value) {
            days.add(PlanDayInput(
              dayOfWeek: entry.key,
              exerciseId: de.exerciseId,
              sortOrder: days.where((d) => d.dayOfWeek == entry.key).length,
              targetSets: de.targetSets,
              targetReps: de.targetReps,
              targetWeightKg: de.targetWeightKg,
              targetDurationSec: de.targetDurationSec,
              restSec: de.restSec,
            ));
          }
        }
        await repo.saveDays(_editingPlanId!, days);
      } else {
        final plan = await repo.create(name, note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim());

        final days = <PlanDayInput>[];
        for (final entry in _schedule.entries) {
          for (int i = 0; i < entry.value.length; i++) {
            final de = entry.value[i];
            days.add(PlanDayInput(
              dayOfWeek: entry.key,
              exerciseId: de.exerciseId,
              sortOrder: i,
              targetSets: de.targetSets,
              targetReps: de.targetReps,
              targetWeightKg: de.targetWeightKg,
              targetDurationSec: de.targetDurationSec,
              restSec: de.restSec,
            ));
          }
        }
        await repo.saveDays(plan.id, days);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }
}

class _DayExercise {
  final int exerciseId;
  final int targetSets;
  final int? targetReps;
  final double? targetWeightKg;
  final int? targetDurationSec;
  final int restSec;

  const _DayExercise({
    required this.exerciseId,
    this.targetSets = 3,
    this.targetReps,
    this.targetWeightKg,
    this.targetDurationSec,
    this.restSec = 90,
  });
}

class _ExercisePickerSheet extends ConsumerWidget {
  final void Function(ExerciseEntity) onSelect;
  const _ExercisePickerSheet({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(exerciseRepoProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      builder: (context, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('选择动作', style: theme.textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<ExerciseEntity>>(
              future: repo.getAll(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.builder(
                  controller: scrollCtrl,
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final ex = snapshot.data![index];
                    final catColor = AppTheme.categoryColors[ex.category] ?? Colors.grey;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: catColor.withAlpha(40),
                        child: Icon(
                          AppTheme.categoryIcons[ex.category] ?? Icons.fitness_center,
                          color: catColor,
                          size: 20,
                        ),
                      ),
                      title: Text(ex.name),
                      subtitle: Text(
                        AppTheme.categoryLabels[ex.category] ?? ex.category,
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => onSelect(ex),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
