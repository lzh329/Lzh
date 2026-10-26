import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/milestone_celebration.dart';

/// 记录体重 FAB —— 快捷录入 + 里程碑庆祝
class WeighInFab extends ConsumerWidget {
  const WeighInFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayMetric =
        ref.watch(dashboardDataProvider).valueOrNull?.todayMetric;
    final hasRecorded = todayMetric != null;

    return FloatingActionButton.extended(
      onPressed: () {
        HapticFeedback.mediumImpact();
        _showQuickWeightInput(context, ref, todayMetric);
      },
      backgroundColor: hasRecorded ? AppColors.primary : null,
      foregroundColor: AppColors.onPrimary,
      icon: Icon(hasRecorded ? Icons.check_circle : Icons.monitor_weight),
      label: Text(
        hasRecorded
            ? '今日 ${(todayMetric.weightKg * 2).toStringAsFixed(1)} 斤 ✓'
            : '记录体重',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  void _showQuickWeightInput(
    BuildContext context,
    WidgetRef ref,
    BodyMetricEntity? existing,
  ) {
    final weightCtrl = TextEditingController(
      text: existing != null ? (existing.weightKg * 2).toStringAsFixed(1) : '',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
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
              const SizedBox(height: 20),
              Text(
                existing != null ? '修改今日体重' : '记录今日体重',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('M月d日 EEEE', 'zh_CN').format(DateTime.now()),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: theme.textTheme.headlineMedium,
                decoration: const InputDecoration(
                  labelText: '体重',
                  suffixText: '斤',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: AppColors.surfaceAlt,
                ),
                onSubmitted: (_) => _doSave(context, ctx, ref, weightCtrl),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => _doSave(context, ctx, ref, weightCtrl),
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('保存', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _doSave(
    BuildContext pageContext,
    BuildContext sheetCtx,
    WidgetRef ref,
    TextEditingController ctrl,
  ) async {
    final weight = double.tryParse(ctrl.text);
    if (weight == null || weight <= 0) {
      if (!sheetCtx.mounted) return;
      ScaffoldMessenger.of(sheetCtx).showSnackBar(
        const SnackBar(content: Text('请输入有效的体重')),
      );
      return;
    }

    // 记录前状态（用于里程碑判断）
    final dashboard = ref.read(dashboardDataProvider).valueOrNull;
    final firstKg = dashboard?.firstMetric?.weightKg;
    final previousKg =
        dashboard?.todayMetric?.weightKg ?? dashboard?.latestMetric?.weightKg;

    final repo = ref.read(bodyMetricRepoProvider);
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final existingEntries = await repo.getAll(from: todayStart, to: today);

    if (existingEntries.isNotEmpty) {
      await repo.update(
        id: existingEntries.first.id,
        date: today,
        weightKg: weight / 2,
      );
    } else {
      await repo.create(date: today, weightKg: weight / 2);
    }

    // ── 里程碑判断：累计减重跨过 5 的倍数 ──
    int? milestone;
    if (firstKg != null && previousKg != null) {
      final oldLoss = firstKg * 2 - previousKg * 2;
      final newLoss = firstKg * 2 - weight;
      for (int m = 5; m <= 200; m += 5) {
        if (oldLoss < m && newLoss >= m) {
          milestone = m;
        }
      }
    }

    ref.invalidate(dashboardDataProvider);
    ref.invalidate(userSettingsProvider);

    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
    if (pageContext.mounted) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(
          content: Text('今日 ${weight.toStringAsFixed(1)} 斤 ✓'),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    if (milestone != null && pageContext.mounted) {
      await showMilestoneCelebration(pageContext, milestone);
    }
  }
}
