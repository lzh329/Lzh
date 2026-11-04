import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';

/// 第一步：选模板（我的模板 + 推荐模板，**没有空白模式**）
class WorkoutLogTemplatePicker extends ConsumerWidget {
  final ValueChanged<WorkoutTemplateEntity> onPick;

  const WorkoutLogTemplatePicker({super.key, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workoutTemplatesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('模板加载失败'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(workoutTemplatesProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (templates) {
        final mine = templates.where((t) => !t.isRecommended).toList();
        final recommended = templates.where((t) => t.isRecommended).toList();

        if (templates.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '还没有可用的模板。\n先到「训练 → 模板」建一个，或者直接用推荐模板。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            const Text(
              '照着模板记：选一套你练过的，下一步会自动带出动作。',
              style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            if (mine.isNotEmpty) ...[
              const _SectionTitle('我的模板'),
              for (final t in mine) _TemplateTile(template: t, onPick: onPick),
              const SizedBox(height: 14),
            ],
            if (recommended.isNotEmpty) ...[
              const _SectionTitle('推荐模板'),
              for (final t in recommended)
                _TemplateTile(template: t, onPick: onPick),
            ],
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final ValueChanged<WorkoutTemplateEntity> onPick;

  const _TemplateTile({required this.template, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(template.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${template.minutes} 分钟 · ${template.previewText}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
        ),
        trailing: const Icon(Icons.chevron_right,
            size: 18, color: AppColors.textTertiary),
        onTap: () => onPick(template),
      ),
    );
  }
}
