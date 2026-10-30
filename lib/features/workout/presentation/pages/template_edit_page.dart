import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/presentation/pages/quick_start_page.dart';
import 'package:fittrack/features/workout/presentation/widgets/exercise_item_editor.dart';
import 'package:fittrack/features/workout/presentation/widgets/exercise_picker_sheet.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_items_list.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_basics_section.dart';

import 'package:fittrack/core/theme/app_colors.dart';

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

  String _existingFocus = '全身'; // focus 已不展示，编辑时沿用旧值
  int _minutes = 15;
  final List<EditItem> _items = [];
  bool _loading = false;
  bool _saving = false;

  static const _green = AppColors.primary;

  @override
  void initState() {
    super.initState();
    if (widget.templateId != null) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final t =
        await ref.read(workoutTemplateRepoProvider).getById(widget.templateId!);
    if (!mounted) return;
    setState(() {
      if (t != null) {
        _nameCtrl.text = t.name;
        _descCtrl.text = t.description ?? '';
        _difficulty = t.difficulty;
        _existingFocus = t.focus;
        _minutes = t.minutes;
        _items
          ..clear()
          ..addAll(t.items.map((i) => EditItem(
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
      // 每行的计量方式已在编辑弹窗里按动作分类定好，这里直接搬运
      final inputs = _items
          .map((i) => TemplateItemInput(
                exerciseId: i.exerciseId,
                targetSets: i.sets,
                targetReps: i.reps,
                targetDurationSec: i.durationSec,
              ))
          .toList();
      // 模板类型由动作构成派生（含任一有氧动作 → cardio），不让用户手选
      final derivedType = deriveTemplateType(_items.map((i) => i.category));
      final desc = _descCtrl.text.trim();

      if (widget.templateId == null) {
        await repo.create(
          name: name,
          difficulty: _difficulty,
          focus: _existingFocus,
          type: derivedType,
          minutes: _minutes,
          description: desc.isEmpty ? null : desc,
          items: inputs,
        );
      } else {
        await repo.update(
          id: widget.templateId!,
          name: name,
          difficulty: _difficulty,
          focus: _existingFocus,
          type: derivedType,
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
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
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
    // 列表与搜索都在 sheet 内部完成（输入即查 ExerciseRepository.search）
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ExercisePickerSheet(
        onPick: (ex) {
          final isTimed = ex.category == 'stretch' ||
              ex.category == 'cardio' ||
              ex.defaultDurationSec != null;
          setState(() {
            _items.add(EditItem(
              exerciseId: ex.id,
              name: ex.name,
              category: ex.category,
              sets: 3,
              reps: isTimed ? null : (ex.defaultReps ?? 12),
              durationSec: isTimed ? (ex.defaultDurationSec ?? 60) : null,
            ));
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _editItem(int index) async {
    // 有氧模板只让填时长：多出的组数/次数格子是有氧里不存在的概念
    // 弹窗形态由该动作自己的分类决定（同一模板可混排力量/有氧）
    final updated = await showExerciseItemEditor(context, item: _items[index]);
    if (updated == null || !mounted) return;
    setState(() => _items[index] = updated);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
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
          TemplateBasicsSection(
            nameCtrl: _nameCtrl,
            descCtrl: _descCtrl,
            difficulty: _difficulty,
            minutes: _minutes,
            onDifficulty: (d) => setState(() => _difficulty = d),
            onMinutes: (m) => setState(() => _minutes = m),
          ),
          const SizedBox(height: 10),
          TemplateItemsList(
            items: _items,
            onAdd: _addExercise,
            onEdit: _editItem,
            onRemove: (i) => setState(() => _items.removeAt(i)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: AppColors.onPrimary,
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
}
