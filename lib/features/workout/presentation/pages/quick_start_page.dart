import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

/// 训练模板数据源（推荐模板 + 我的模板）
final workoutTemplatesProvider =
    FutureProvider<List<WorkoutTemplateEntity>>((ref) {
  return ref.watch(workoutTemplateRepoProvider).getAll();
});

const _green = Color(0xFF66BB6A);
const _amber = Color(0xFFFFA726);

/// 快速训练页 —— 模板化开练（v2，模板已数据库化）
class QuickStartPage extends ConsumerStatefulWidget {
  const QuickStartPage({super.key});

  @override
  ConsumerState<QuickStartPage> createState() => _QuickStartPageState();
}

class _QuickStartPageState extends ConsumerState<QuickStartPage> {
  bool _starting = false;

  Future<void> _startTemplate(WorkoutTemplateEntity template) async {
    if (_starting) return;
    setState(() => _starting = true);

    try {
      final slots = template.items
          .map((i) => ExerciseSlot(
                exerciseId: i.exerciseId,
                exerciseName: i.exerciseName,
                category: i.category,
                targetSets: i.targetSets,
                targetReps: i.targetReps,
                targetDurationSec: i.targetDurationSec,
              ))
          .toList();

      if (!mounted) return;
      if (slots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该模板还没有动作，请先编辑')),
        );
        return;
      }
      context.pushReplacement('/workout/active', extra: slots);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(workoutTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('快速训练'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建模板',
            onPressed: () => context.push('/workout/template-edit'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(workoutTemplatesProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (templates) {
          final recommended =
              templates.where((t) => t.isRecommended).toList();
          final mine = templates.where((t) => !t.isRecommended).toList();
          final minMinutes = recommended.isEmpty
              ? 10
              : recommended
                  .map((t) => t.minutes)
                  .reduce((a, b) => a < b ? a : b);
          final totalExercises = recommended.fold<int>(
              0, (sum, t) => sum + t.items.length);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
            children: [
              // ── 节奏选择卡 ──
              Card(
                color: const Color(0xFF2A2014),
                margin: const EdgeInsets.only(bottom: 18),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt, size: 18, color: _amber),
                          const SizedBox(width: 8),
                          Text('选择节奏，马上开练',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '从任意拉伸到高强度燃烧，先完成一组数据就开练',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white60),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _MiniStat(
                              value: '$minMinutes 分钟', label: '最短时长'),
                          _MiniStat(
                              value: '${recommended.length} 个',
                              label: '推荐模板'),
                          _MiniStat(
                              value: '$totalExercises 个', label: '动作数'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => context.push('/workout/custom'),
                          icon: const Icon(Icons.tune, size: 18),
                          label: const Text('自定义训练'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── 推荐模板 ──
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Text('推荐模板', style: theme.textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  '选择一个模板，立即进入训练',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              ...recommended.map((t) => _TemplateCard(
                    template: t,
                    starting: _starting,
                    onStart: () => _startTemplate(t),
                  )),

              const SizedBox(height: 12),

              // ── 我的模板 ──
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('我的模板',
                        style: theme.textTheme.titleMedium),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.push('/workout/template-edit'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  '保存你常做的训练组合',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              if (mine.isEmpty)
                Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () => context.push('/workout/template-edit'),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.bookmark_add_outlined,
                                size: 32,
                                color: theme.colorScheme.outline),
                            const SizedBox(height: 8),
                            Text(
                              '还没有自定义模板\n点击创建你的第一个组合',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                ...mine.map((t) => _TemplateCard(
                      template: t,
                      starting: _starting,
                      onStart: () => _startTemplate(t),
                      onEdit: () => context
                          .push('/workout/template-edit?id=${t.id}'),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;

  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, fontSize: 11)),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final bool starting;
  final VoidCallback onStart;
  final VoidCallback? onEdit;

  const _TemplateCard({
    required this.template,
    required this.starting,
    required this.onStart,
    this.onEdit,
  });

  static const _accentColors = {
    'green': Color(0xFF66BB6A),
    'orange': Color(0xFFFB8C00),
    'red': Color(0xFFEF5350),
    'cyan': Color(0xFF26C6DA),
    'purple': Color(0xFFAB47BC),
  };

  static const _accentIcons = {
    'green': Icons.fitness_center,
    'orange': Icons.local_fire_department,
    'red': Icons.bolt,
    'cyan': Icons.business_center,
    'purple': Icons.nightlight_round,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        _accentColors[template.accentKey] ?? _green;
    final icon = _accentIcons[template.accentKey] ?? Icons.fitness_center;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(34),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              template.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          _Tag(text: template.difficulty),
                          const SizedBox(width: 4),
                          _Tag(text: template.focus),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template.description ?? '',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${template.minutes}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: accent),
                    ),
                    Text('分钟',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              template.previewText,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_note,
                        size: 20, color: Colors.white38),
                    tooltip: '编辑模板',
                    onPressed: onEdit,
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: starting ? null : onStart,
                      child: const Text('开始训练',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }
}
