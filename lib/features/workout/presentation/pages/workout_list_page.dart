import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

/// 全部训练（训练页数据源）
final _allWorkoutsProvider = FutureProvider<List<WorkoutEntity>>((ref) {
  return ref.watch(workoutRepoProvider).getAll();
});

/// 称重日期标记
final _weighDatesProvider = FutureProvider<Set<DateTime>>((ref) async {
  final metrics = await ref.watch(bodyMetricRepoProvider).getAll();
  return metrics
      .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
      .toSet();
});

/// 动作名映射
final _exerciseNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final list = await ref.watch(exerciseRepoProvider).getAll();
  return {for (final e in list) e.id: e.name};
});

const _green = Color(0xFF66BB6A);
const _orange = Color(0xFFFF9800);
const _blue = Color(0xFF42A5F5);

/// 训练记录页 —— 周视图 + 当天记录（v2）
class WorkoutListPage extends ConsumerStatefulWidget {
  const WorkoutListPage({super.key});

  @override
  ConsumerState<WorkoutListPage> createState() => _WorkoutListPageState();
}

class _WorkoutListPageState extends ConsumerState<WorkoutListPage> {
  late DateTime _selected;
  late DateTime _weekStart; // 周一

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _weekStart = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  void _shiftWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _selected = _weekStart;
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final workoutsAsync = ref.watch(_allWorkoutsProvider);
    final weighDates =
        ref.watch(_weighDatesProvider).valueOrNull ?? const <DateTime>{};
    final exerciseNames =
        ref.watch(_exerciseNamesProvider).valueOrNull ?? const <int, String>{};
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练记录'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: '训练计划',
            onPressed: () => context.push('/plan'),
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '训练统计',
            onPressed: () => context.push('/workout/stats'),
          ),
        ],
      ),
      body: workoutsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(_allWorkoutsProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (workouts) {
          final dayWorkouts = workouts
              .where((w) => _sameDay(w.date, _selected))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          final workoutDates = workouts
              .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
              .toSet();

          return Column(
            children: [
              _WeekStrip(
                weekStart: _weekStart,
                selected: _selected,
                markedDates: workoutDates,
                weighDates: weighDates,
                onSelect: (d) => setState(() => _selected = d),
                onPrev: () => _shiftWeek(-1),
                onNext: () => _shiftWeek(1),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                child: Row(
                  children: [
                    Text(
                      _sameDay(_selected, today)
                          ? '今天'
                          : DateFormat('M月d日 EEEE', 'zh_CN')
                              .format(_selected),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _green,
                      ),
                    ),
                    const Spacer(),
                    const _LegendDot(color: _orange, label: '训练'),
                    const SizedBox(width: 12),
                    const _LegendDot(color: _blue, label: '称重'),
                  ],
                ),
              ),
              Divider(height: 1, color: Colors.white.withAlpha(16)),
              Expanded(
                child: dayWorkouts.isEmpty
                    ? _EmptyState(
                        onStart: () => context.push('/workout/quick-start'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: dayWorkouts.length,
                        itemBuilder: (_, i) => _WorkoutCard(
                          workout: dayWorkouts[i],
                          exerciseNames: exerciseNames,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _green,
        foregroundColor: Colors.black,
        onPressed: () => context.push('/workout/quick-start'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ───────────────────── 周日期条 ─────────────────────

class _WeekStrip extends StatelessWidget {
  final DateTime weekStart;
  final DateTime selected;
  final Set<DateTime> markedDates;
  final Set<DateTime> weighDates;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekStrip({
    required this.weekStart,
    required this.selected,
    required this.markedDates,
    required this.weighDates,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('M月d日');
    final end = weekStart.add(const Duration(days: 6));
    const labels = ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: onPrev,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${fmt.format(weekStart)} - ${fmt.format(end)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '选择日期查看当天训练',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onNext,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              for (int i = 0; i < 7; i++)
                Builder(
                  builder: (_) {
                    final d = weekStart.add(Duration(days: i));
                    final day = DateTime(d.year, d.month, d.day);
                    return Expanded(
                      child: _DayCell(
                        date: d,
                        label: labels[i],
                        selected: _sameDay(d, selected),
                        hasMark: markedDates.contains(day),
                        hasWeight: weighDates.contains(day),
                        onTap: () => onSelect(d),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final String label;
  final bool selected;
  final bool hasMark;
  final bool hasWeight;
  final VoidCallback onTap;

  const _DayCell({
    required this.date,
    required this.label,
    required this.selected,
    required this.hasMark,
    required this.hasWeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _green.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _green : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? _green : Colors.white54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? _green : Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasMark)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _orange,
                      ),
                    ),
                  if (hasMark && hasWeight) const SizedBox(width: 3),
                  if (hasWeight)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: _blue,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── 其他组件 ─────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onStart;

  const _EmptyState({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.self_improvement, size: 64, color: Colors.white.withAlpha(40)),
          const SizedBox(height: 16),
          Text(
            '暂无训练记录',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black87,
            ),
            onPressed: onStart,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('开始训练'),
          ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends StatelessWidget {
  final WorkoutEntity workout;
  final Map<int, String> exerciseNames;

  const _WorkoutCard({required this.workout, required this.exerciseNames});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final names = workout.sets
        .map((s) => exerciseNames[s.exerciseId] ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(' · ');

    String? durationInfo;
    if (workout.durationSec != null) {
      final m = workout.durationSec! ~/ 60;
      final s = workout.durationSec! % 60;
      durationInfo = m > 0 ? '$m分$s秒' : '$s秒';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => context.push('/workout/${workout.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _green.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center, size: 18, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      names.isEmpty ? '训练' : names,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${workout.sets.length} 组'
                      '${durationInfo != null ? ' · $durationInfo' : ''}'
                      ' · ${DateFormat('HH:mm').format(workout.date)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
