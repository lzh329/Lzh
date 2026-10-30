import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/widgets/shimmer.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/exercise/domain/repositories/exercise_repository.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 拉伸动作指导（文字说明）
const _stretchGuides = {
  '腿部拉伸': [
    '🧘 股四头肌拉伸',
    '  站立，手扶墙，弯曲右膝，右手抓住右脚踝',
    '  将脚跟拉向臀部，感受大腿前侧拉伸',
    '  保持 20-30 秒，换腿重复',
    '',
    '🧘 腘绳肌拉伸',
    '  坐在地上，双腿伸直',
    '  身体前倾，双手尽量触碰脚尖',
    '  保持背部挺直，感受大腿后侧拉伸',
    '  保持 20-30 秒',
    '',
    '🧘 小腿拉伸',
    '  面对墙站立，双手扶墙',
    '  右腿后撤，脚跟压地，左腿弯曲',
    '  感受右小腿后侧拉伸，保持 20-30 秒',
    '  换腿重复',
  ],
  '肩背拉伸': [
    '🧘 肩部环绕',
    '  站立，双肩同时向前画圆 10 次',
    '  再向后画圆 10 次，幅度逐渐加大',
    '',
    '🧘 三角肌拉伸',
    '  右臂横过胸前，左手按住右上臂',
    '  轻轻将右臂拉向胸部',
    '  保持 20-30 秒，换臂重复',
    '',
    '🧘 上背部拉伸',
    '  双手交叉抱于胸前',
    '  含胸弓背，感受上背部拉伸',
    '  保持 15-20 秒，重复 3 次',
    '',
    '🧘 猫牛式',
    '  四肢着地，吸气时抬头塌腰（牛式）',
    '  呼气时低头拱背（猫式）',
    '  缓慢交替，重复 8-10 次',
  ],
  '全身拉伸': [
    '🧘 全身伸展',
    '  站立，双手举过头顶交叉握紧',
    '  掌心向上推，同时踮起脚尖',
    '  感受全身从指尖到脚尖的拉伸',
    '  保持 15 秒，放松，重复 3 次',
    '',
    '🧘 婴儿式',
    '  跪坐，上身向前趴在大腿上',
    '  额头贴地，双臂向前伸展',
    '  深呼吸，保持 30-60 秒',
    '  放松整个背部和肩部',
    '',
    '🧘 下犬式',
    '  从四肢着地开始，双手与肩同宽',
    '  臀部向上抬起，腿伸直',
    '  脚跟尽量踩地，头放松于双臂间',
    '  保持 20-30 秒',
  ],
};

class ExerciseManagePage extends ConsumerStatefulWidget {
  const ExerciseManagePage({super.key});

  @override
  ConsumerState<ExerciseManagePage> createState() => _ExerciseManagePageState();
}

class _ExerciseManagePageState extends ConsumerState<ExerciseManagePage> {
  String _selectedCategory = 'all';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(exerciseRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('动作库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showEditDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: '搜索动作...',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _CategoryChip(
                    label: '全部',
                    value: 'all',
                    selected: _selectedCategory,
                    onTap: (v) => setState(() => _selectedCategory = v)),
                ...AppTheme.categoryLabels.entries.map(
                  (e) => _CategoryChip(
                      label: e.value,
                      value: e.key,
                      selected: _selectedCategory,
                      onTap: (v) => setState(() => _selectedCategory = v)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<ExerciseEntity>>(
              future: _getExercises(repo),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const ShimmerList();
                }
                final exercises = snapshot.data ?? [];
                if (exercises.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(22),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.fitness_center,
                              size: 30, color: AppColors.primary),
                        ),
                        const SizedBox(height: 14),
                        Text('暂无匹配动作',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: exercises.length,
                  itemBuilder: (context, index) {
                    final ex = exercises[index];
                    final catColor = AppTheme.categoryColors[ex.category] ??
                        AppColors.textTertiary;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: catColor.withAlpha(32),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          AppTheme.categoryIcons[ex.category] ??
                              Icons.fitness_center,
                          color: catColor,
                          size: 18,
                        ),
                      ),
                      title: Text(ex.name, style: theme.textTheme.bodyLarge),
                      subtitle: Text(
                        '${AppTheme.categoryLabels[ex.category] ?? ex.category}${ex.muscleGroup != null ? ' · ${ex.muscleGroup}' : ''}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                      onTap: ex.category == 'stretch' &&
                              _stretchGuides.containsKey(ex.name)
                          ? () => _showStretchGuide(context, ex.name)
                          : null,
                      trailing: ex.isCustom
                          ? PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') {
                                  _showEditDialog(context, exercise: ex);
                                }
                                if (action == 'delete') {
                                  _confirmDelete(context, ex);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                    value: 'delete',
                                    child: Text('删除',
                                        style: TextStyle(
                                            color: AppColors.danger))),
                              ],
                            )
                          : null,
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

  Future<List<ExerciseEntity>> _getExercises(ExerciseRepository repo) async {
    if (_searchQuery.isNotEmpty) return repo.search(_searchQuery);
    if (_selectedCategory == 'all') return repo.getAll();
    return repo.getByCategory(_selectedCategory);
  }

  void _showEditDialog(BuildContext context, {ExerciseEntity? exercise}) {
    final nameCtrl = TextEditingController(text: exercise?.name ?? '');
    final muscleCtrl = TextEditingController(text: exercise?.muscleGroup ?? '');
    String category = exercise?.category ?? 'strength';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(exercise == null ? '添加动作' : '编辑动作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: '动作名称', isDense: true),
                  autofocus: true),
              const SizedBox(height: 12),
              TextField(
                  controller: muscleCtrl,
                  decoration: const InputDecoration(
                      labelText: '目标肌群（可选）', isDense: true)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration:
                    const InputDecoration(labelText: '分类', isDense: true),
                items: AppTheme.categoryLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final repo = ref.read(exerciseRepoProvider);
                if (exercise == null) {
                  await repo.create(
                      name,
                      category,
                      muscleCtrl.text.trim().isEmpty
                          ? null
                          : muscleCtrl.text.trim());
                } else {
                  await repo.update(ExerciseEntity(
                    id: exercise.id,
                    name: name,
                    category: category,
                    muscleGroup: muscleCtrl.text.trim().isEmpty
                        ? null
                        : muscleCtrl.text.trim(),
                    isCustom: exercise.isCustom,
                  ));
                }
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ExerciseEntity exercise) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除动作'),
        content: Text('确定要删除「${exercise.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
            onPressed: () async {
              await ref.read(exerciseRepoProvider).delete(exercise.id);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showStretchGuide(BuildContext context, String name) {
    final steps = _stretchGuides[name];
    if (steps == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('$name 指导', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...steps.map((line) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line.isEmpty ? ' ' : line,
                    style: TextStyle(
                      fontSize: line.startsWith('🧘') ? 14 : 13,
                      fontWeight: line.startsWith('🧘')
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: line.startsWith('🧘')
                          ? Theme.of(ctx).colorScheme.primary
                          : Theme.of(ctx).colorScheme.onSurface,
                      height: 1.5,
                    ),
                  ),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;
  const _CategoryChip(
      {required this.label,
      required this.value,
      required this.selected,
      required this.onTap});

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
