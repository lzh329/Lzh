import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart' show WaterLogEntry;

final _waterHistoryProvider = FutureProvider<List<WaterLogEntry>>((ref) =>
    ref.watch(waterRepoProvider).getHistory());

final _todayCupsProvider = FutureProvider<int>((ref) {
  return ref.watch(waterRepoProvider).getTodayCups();
});

class WaterPage extends ConsumerWidget {
  const WaterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_waterHistoryProvider);
    final todayCupsAsync = ref.watch(_todayCupsProvider);
    final theme = Theme.of(context);

    final todayCups = todayCupsAsync.valueOrNull ?? 0;
    const targetCups = 8;

    return Scaffold(
      appBar: AppBar(title: const Text('饮水记录')),
      body: Column(
        children: [
          // 今日饮水大卡片
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  const Text('💧', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text('今日饮水', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('$todayCups / $targetCups 杯',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: todayCups >= targetCups ? Colors.green : theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    )),
                  const SizedBox(height: 4),
                  if (todayCups >= targetCups)
                    const Text('🎉 已达标！', style: TextStyle(color: Colors.green)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (todayCups / targetCups).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      color: todayCups >= targetCups ? Colors.green : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CupButton(
                        icon: Icons.remove,
                        label: '减少',
                        onTap: todayCups > 0
                            ? () => _adjustCup(ref, false)
                            : null,
                      ),
                      const SizedBox(width: 24),
                      _CupButton(
                        icon: Icons.add,
                        label: '增加',
                        primary: true,
                        onTap: () => _adjustCup(ref, true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 历史记录
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.history, size: 18, color: theme.colorScheme.outline),
                const SizedBox(width: 6),
                Text('历史记录', style: theme.textTheme.titleSmall),
              ],
            ),
          ),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(child: Text('加载失败')),
              data: (history) {
                if (history.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.water_drop, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        Text('还没有饮水记录', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final entry = history[index];
                    final dateFmt = DateFormat('M月d日 EEEE', 'zh_CN');
                    final isToday = DateTime.now().year == entry.date.year &&
                        DateTime.now().month == entry.date.month &&
                        DateTime.now().day == entry.date.day;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (entry.cups >= targetCups ? Colors.green : theme.colorScheme.primaryContainer).withAlpha(80),
                        child: Text('${entry.cups}',
                          style: TextStyle(
                            color: entry.cups >= targetCups ? Colors.green : theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          )),
                      ),
                      title: Text(isToday ? '今天' : dateFmt.format(entry.date)),
                      subtitle: Text('$entry.cups 杯 (${entry.cups * 200}ml)'),
                      trailing: entry.cups >= targetCups
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
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

class _CupButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;
  const _CupButton({
    required this.icon,
    required this.label,
    this.primary = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return primary
        ? FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
          )
        : OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: OutlinedButton.styleFrom(minimumSize: const Size(100, 44)),
          );
  }
}
