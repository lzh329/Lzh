import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterLogEntry;

import 'package:fittrack/core/theme/app_colors.dart';

final _waterHistoryProvider = FutureProvider<List<WaterLogEntry>>(
    (ref) => ref.watch(waterRepoProvider).getHistory());

final _todayCupsProvider = FutureProvider<int>((ref) {
  return ref.watch(waterRepoProvider).getTodayCups();
});

const _blue = AppColors.info;

/// 饮水页 —— v2 视觉：杯子网格打卡 + 历史记录
class WaterPage extends ConsumerWidget {
  const WaterPage({super.key});

  static const _targetCups = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(_waterHistoryProvider);
    final todayCups = ref.watch(_todayCupsProvider).valueOrNull ?? 0;
    final reached = todayCups >= _targetCups;

    return Scaffold(
      appBar: AppBar(title: const Text('饮水记录')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ── 主卡：杯子网格 ──
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _blue.withAlpha(32),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.water_drop,
                            size: 16, color: _blue),
                      ),
                      const SizedBox(width: 10),
                      Text('今日饮水', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      if (reached)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _blue.withAlpha(26),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: _blue.withAlpha(110), width: 0.8),
                          ),
                          child: const Text(
                            '已完成',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _blue),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$todayCups',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: _blue,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '/ $_targetCups 杯',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (int i = 0; i < _targetCups; i++)
                        _CupIcon(filled: i < todayCups),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    reached
                        ? '今日饮水目标已完成，保持得很好'
                        : '还差 ${_targetCups - todayCups} 杯 · 约 ${((_targetCups - todayCups) * 0.2).toStringAsFixed(1)} L',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: todayCups > 0
                                ? () => _adjustCup(ref, false)
                                : null,
                            icon: const Icon(Icons.remove, size: 18),
                            label: const Text('−1 杯'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.borderStrong),
                              foregroundColor: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 44,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.infoStrong,
                              foregroundColor: AppColors.surface,
                            ),
                            onPressed: () => _adjustCup(ref, true),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('＋1 杯',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── 历史记录 ──
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('历史记录', style: theme.textTheme.titleSmall),
          ),
          historyAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text('加载失败',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textTertiary)),
                ),
              ),
            ),
            data: (history) {
              if (history.isEmpty) {
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.water_drop_outlined,
                              size: 34, color: AppColors.textTertiary),
                          const SizedBox(height: 8),
                          Text(
                            '还没有饮水记录\n点击上方「＋1 杯」开始打卡',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (int i = 0; i < history.length; i++) ...[
                      _HistoryTile(entry: history[i]),
                      if (i < history.length - 1)
                        const Divider(
                          height: 1,
                          indent: 62,
                          endIndent: 16,
                          color: AppColors.border,
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _adjustCup(WidgetRef ref, bool increment) async {
    final repo = ref.read(waterRepoProvider);
    if (increment) {
      await repo.incrementCup();
    } else {
      await repo.decrementCup();
    }
    ref.invalidate(_todayCupsProvider);
    ref.invalidate(_waterHistoryProvider);
    ref.invalidate(dashboardDataProvider);
  }
}

class _CupIcon extends StatelessWidget {
  final bool filled;

  const _CupIcon({required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 32,
      decoration: BoxDecoration(
        color: filled ? _blue : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: filled ? _blue : AppColors.borderStrong,
          width: 0.8,
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final WaterLogEntry entry;

  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = now.year == entry.date.year &&
        now.month == entry.date.month &&
        now.day == entry.date.day;
    final reached = entry.cups >= 8;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _blue.withAlpha(reached ? 40 : 22),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          '${entry.cups}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: reached ? _blue : AppColors.textSecondary,
          ),
        ),
      ),
      title: Text(
        isToday ? '今天' : DateFormat('M月d日 EEEE', 'zh_CN').format(entry.date),
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        '${entry.cups} 杯 · ${entry.cups * 200} ml',
        style:
            theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
      trailing: reached
          ? const Icon(Icons.check_circle, color: _blue, size: 20)
          : null,
    );
  }
}
