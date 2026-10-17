import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';

/// 模板编辑页 —— 新建 / 编辑训练模板
class TemplateEditPage extends ConsumerStatefulWidget {
  final int? templateId; // null = 新建

  const TemplateEditPage({super.key, this.templateId});

  @override
  ConsumerState<TemplateEditPage> createState() => _TemplateEditPageState();
}

class _TemplateEditPageState extends ConsumerState<TemplateEditPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _difficulty = '入门';
  String _focus = '全身';
  int _minutes = 15;
  final List<_EditItem> _items = [];
  bool _loading = false;
  bool _saving = false;

  static const _green = Color(0xFF66BB6A);
  static const _difficulties = ['入门', '中阶', '高阶'];
  static const _focuses = ['全身', '放松', '碎片'];

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final t = await ref
        .read(workoutTemplateRepoProvider)
        .getById(widget.templateId!);
    if (!mounted) return;
    setState(() {
      if (t != null) {
        _nameCtrl.text = t.name;
        _descCtrl.text = t.description ?? '';
        _difficulty = t.difficulty;
        _focus = t.focus;
        _minutes = t.minutes;
        _items
          ..clear()
          ..addAll(t.items.map((i) => _EditItem(
                exerciseId: i.exerciseId,
                name: i.exerciseName,
                category: i.category,
                sets: i.targetSets,
                reps: i.targetReps,
                durationSec: i.targetDurationSec,
              )));
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请输入模板名称');
      return;
    }
    if (_items.isEmpty) {
      _snack('请至少添加一个动作');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(workoutTemplateRepoProvider);
      final inputs = _items
          .map((i) => TemplateItemInput(
                exerciseId: i.exerciseId,
                targetSets: i.sets,
                targetReps: i.reps,
                targetDurationSec: i.durationSec,
              ))
          .toList();
      final desc = _descCtrl.text.trim();

      if (widget.templateId == null) {
        await repo.create(
          name: name,
          difficulty: _difficulty,
          focus: _focus,
          minutes: _minutes,
          description: desc.isEmpty ? null : desc,
          items: inputs,
        );
      } else {
        await repo.update(
          id: widget.templateId!,
          name: name,
          difficulty: _difficulty,
          focus: _focus,
          minutes: _minutes,
          description: desc.isEmpty ? null : desc,
          items: inputs,
        );
      }

      ref.invalidate(workoutTemplatesProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模板'),
        content: const Text('确定要删除这个模板吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(workoutTemplateRepoProvider).delete(widget.templateId!);
    ref.invalidate(workoutTemplatesProvider);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addExercise() async {
    final exercises = await ref.read(exerciseRepoProvider).getAll();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExercisePickerSheet(
        exercises: exercises,
        onPick: (ex) {
          final isTimed = ex.category == 'stretch' || ex.category == 'cardio';
          setState(() {
            _items.add(_EditItem(
              exerciseId: ex.id,
              name: ex.name,
              category: ex.category,
              sets: 3,
              reps: isTimed ? null : (ex.defaultReps ?? 12),
              durationSec:
                  isTimed ? (ex.defaultDurationSec ?? 60) : null,
            ));
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final setsCtrl = TextEditingController(text: '${item.sets}');
    final isTimed = item.reps == null;
    final repsCtrl = TextEditingController(text: item.reps?.toString() ?? '');
    final durCtrl =
        TextEditingController(text: item.durationSec?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: setsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '组数',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: isTimed ? durCtrl : repsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isTimed ? '每组时长（秒）' : '每组次数',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final sets = int.tryParse(setsCtrl.text) ?? item.sets;
              setState(() {
                _items[index] = _EditItem(
                  exerciseId: item.exerciseId,
                  name: item.name,
                  category: item.category,
                  sets: sets.clamp(1, 20),
                  reps: isTimed
                      ? null
                      : (int.tryParse(repsCtrl.text) ?? item.reps),
                  durationSec: isTimed
                      ? (int.tryParse(durCtrl.text) ?? item.durationSec)
                      : null,
                );
              });
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.templateId == null ? '新建模板' : '编辑模板'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
          if (widget.templateId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除模板',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          TextField(
            controller: _nameCtrl,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '模板名称',
              hintText: '例如：周末燃脂',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          _label(theme, '难度'),
          Wrap(
            spacing: 8,
            children: _difficulties
                .map((d) => ChoiceChip(
                      label: Text(d, style: const TextStyle(fontSize: 12)),
                      selected: _difficulty == d,
                      onSelected: (_) => setState(() => _difficulty = d),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          _label(theme, '部位'),
          Wrap(
            spacing: 8,
            children: _focuses
                .map((f) => ChoiceChip(
                      label: Text(f, style: const TextStyle(fontSize: 12)),
                      selected: _focus == f,
                      onSelected: (_) => setState(() => _focus = f),
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _label(theme, '预计时长'),
              const Spacer(),
              Text('$_minutes 分钟',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _green)),
            ],
          ),
          Slider(
            value: _minutes.toDouble(),
            min: 5,
            max: 60,
            divisions: 11,
            label: '$_minutes 分钟',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descCtrl,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '一句话描述（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('动作（${_items.length}）',
                  style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: _addExercise,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加动作'),
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          if (_items.isEmpty)
            Card(
              margin: const EdgeInsets.only(top: 4),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Center(
                  child: Text(
                    '还没有动作，点击「添加动作」从动作库选择',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              ),
            )
          else
            ..._items.asMap().entries.map((e) {
              final item = e.value;
              final detail = item.reps != null
                  ? '${item.sets} 组 × ${item.reps} 次'
                  : '${item.sets} 组 × ${item.durationSec ?? 0} 秒';
              return Card(
                margin: const EdgeInsets.only(top: 8),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  title: Text(item.name,
                      style: theme.textTheme.bodyMedium),
                  subtitle: Text(detail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.tune, size: 18),
                        tooltip: '调整组数/次数',
                        onPressed: () => _editItem(e.key),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: '移除',
                        onPressed: () =>
                            setState(() => _items.removeAt(e.key)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.black87,
              ),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中...' : '保存模板',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline)),
    );
  }
}

class _EditItem {
  final int exerciseId;
  final String name;
  final String category;
  final int sets;
  final int? reps;
  final int? durationSec;

  const _EditItem({
    required this.exerciseId,
    required this.name,
    required this.category,
    required this.sets,
    this.reps,
    this.durationSec,
  });
}

class _ExercisePickerSheet extends StatelessWidget {
  final List<ExerciseEntity> exercises;
  final ValueChanged<ExerciseEntity> onPick;

  const _ExercisePickerSheet({
    required this.exercises,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.65,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('选择动作', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: exercises.length,
              itemBuilder: (_, i) {
                final ex = exercises[i];
                return ListTile(
                  dense: true,
                  title: Text(ex.name, style: theme.textTheme.bodyMedium),
                  subtitle: Text(ex.muscleGroup ?? '',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                  trailing: const Icon(Icons.add_circle_outline, size: 20),
                  onTap: () => onPick(ex),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
