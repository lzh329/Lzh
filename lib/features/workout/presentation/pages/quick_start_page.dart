import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/workout_templates.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

/// 快速训练页 —— 模板化开练（v2）
///
/// 顶部：节奏选择卡（自定义训练入口）
/// 中部：推荐模板（5 个内置模板）
/// 底部：我的模板（占位）
class QuickStartPage extends ConsumerStatefulWidget {
  const QuickStartPage({super.key});

  @override
  ConsumerState<QuickStartPage> createState() => _QuickStartPageState();
}

class _QuickStartPageState extends ConsumerState<QuickStartPage> {
  bool _starting = false;

  Future<void> _startTemplate(WorkoutTemplate template) async {
    if (_starting) return;
    setState(() => _starting = true);

    try {
      final exercises = await ref.read(exerciseRepoProvider).getAll();
      final byName = {for (final e in exercises) e.name: e};

      final slots = <ExerciseSlot>[];
      for (final te in template.exercises) {
        final ex = byName[te.name];
        if (ex == null) continue;
        slots.add(ExerciseSlot(
          exerciseId: ex.id,
          exerciseName: ex.name,
          category: ex.category,
          targetSets: te.sets,
          targetReps: te.reps ?? ex.defaultReps,
          targetWeightKg: ex.defaultWeightKg,
          targetDurationSec: te.durationSec ?? ex.defaultDurationSec,
        ));
      }

      if (!mounted) return;
      if (slots.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('模板动作匹配失败，请检查动作库')),
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
    final totalExercises = recommendedTemplates.fold<int>(
        0, (sum, t) => sum + t.exercises.length);
    final minMinutes = recommendedTemplates
        .map((t) => t.minutes)
        .reduce((a, b) => a < b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('快速训练'), centerTitle: false),
      body: ListView(
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
                      const Icon(Icons.bolt, size: 18, color: Color(0xFFFFA726)),
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
                      _MiniStat(value: '$minMinutes 分钟', label: '最短时长'),
                      _MiniStat(
                          value: '${recommendedTemplates.length} 个', label: '推荐模板'),
                      _MiniStat(value: '$totalExercises 个', label: '动作数'),
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
          ...recommendedTemplates.map((t) => _TemplateCard(
                template: t,
                starting: _starting,
                onStart: () => _startTemplate(t),
              )),

          const SizedBox(height: 12),

          // ── 我的模板 ──
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text('我的模板', style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              '保存你常做的训练组合',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bookmark_border,
                        size: 32, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    Text(
                      '还没有自定义模板\n完成训练后可存为模板（即将上线）',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
  final WorkoutTemplate template;
  final bool starting;
  final VoidCallback onStart;

  const _TemplateCard({
    required this.template,
    required this.starting,
    required this.onStart,
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
    final accent = _accentColors[template.accentKey] ?? const Color(0xFF66BB6A);
    final icon = _accentIcons[template.accentKey] ?? Icons.fitness_center;

    final preview = template.exercises
        .map((e) => e.reps != null
            ? '${e.name} ${e.sets}×${e.reps}'
            : '${e.name} ${e.sets}×${e.durationSec}s')
        .join(' · ');

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
                        template.description,
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
              preview,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_note,
                      size: 20, color: Colors.white38),
                  tooltip: '编辑模板',
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('模板编辑即将上线')),
                    );
                  },
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
