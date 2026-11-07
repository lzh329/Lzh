import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/week_summary.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_empty_state.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_record_card.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_week_strip.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_week_summary.dart';

/// 称重日期（周条蓝点用；只读 `body_metrics`，不新增表）
final _weighDatesProvider = FutureProvider<Set<DateTime>>((ref) async {
  final metrics = await ref.watch(bodyMetricRepoProvider).getAll();
  return metrics
      .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
      .toSet();
});

/// 动作名映射（记录卡的「深蹲 · 平板支撑」）
final _exerciseNamesProvider = FutureProvider<Map<int, String>>((ref) async {
  final list = await ref.watch(exerciseRepoProvider).getAll();
  return {for (final e in list) e.id: e.name};
});

/// 训练记录页（T6–T12）—— 从 `workout_list_page.dart` **就地改造**而来。
///
/// 三块自上而下：周日期条 → 本周摘要 → 选中日明细。
/// 为什么不重写：日历跨周、同日多次训练排序、称重/训练双标记这些边界逻辑
/// 已经在原页面跑了一年，重写等于重新踩一遍，而且这次没有测试保护（决策 10）。
///
/// 图表不在这里：`/workout/stats` 有 561 行、PR/容量等重内容。两个页面各管一件事。
class WorkoutRecordsPage extends ConsumerStatefulWidget {
  const WorkoutRecordsPage({super.key});

  @override
  ConsumerState<WorkoutRecordsPage> createState() => _WorkoutRecordsPageState();
}

class _WorkoutRecordsPageState extends ConsumerState<WorkoutRecordsPage> {
  late DateTime _selected;
  late DateTime _weekStart; // 周一

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _weekStart = WeekSummaryCalc.weekOf(now);
  }

  /// 翻周：选中日 = 新周的周一（T8）
  void _shiftWeek(int delta) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * delta));
      _selected = _weekStart;
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 把内容包成「可下拉刷新 + 填满视口」：空态也要能下拉刷新
  /// （之前空态不是滚动体，下拉手势无处可拉）。
  Widget _refreshable(Widget child) => RefreshIndicator(
        onRefresh: () => ref.refresh(workoutHistoryProvider.future),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final workoutsAsync = ref.watch(workoutHistoryProvider);
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
          // 主按钮放**右侧第一个**：这是本页最常做的事（记一笔是"事后补记"，
          // 而看统计/看计划是低频动作）。用带文案的按钮而不是纯图标 ——
          // "记一笔"三个字本身就是产品语言，图标表达不出来。
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilledButton.icon(
              onPressed: () => context.push(
                  '/workout/log/new?date=${DateFormat('yyyy-MM-dd').format(_selected)}'),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('记一笔'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(workoutHistoryProvider),
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
                onPressed: () => ref.invalidate(workoutHistoryProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (workouts) {
          // ── 全程无记录（T16）：整页空态，连周条都不画 ──
          if (workouts.isEmpty) {
            return _refreshable(WorkoutEmptyState(
              icon: Icons.self_improvement,
              title: '还没有训练记录',
              subtitle: '练完一次，这里就会记下来',
              buttonLabel: '现在去练',
              // ⚠️ go 不是 push：push 到 Tab 路由会把底部导航叠掉
              onStart: () => context.go('/workout'),
            ));
          }

          final dayWorkouts =
              workouts.where((w) => _sameDay(w.date, _selected)).toList()
                ..sort((a, b) => b.date.compareTo(a.date));
          final workoutDates = workouts
              .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
              .toSet();

          final summary = WeekSummaryCalc.of(
            workouts
                .map((w) => (date: w.date, durationSec: w.durationSec))
                .toList(),
            now: today,
          );

          return Column(
            children: [
              // ① 周日期条（图例已收进组件内部）
              WorkoutWeekStrip(
                weekStart: _weekStart,
                selected: _selected,
                markedDates: workoutDates,
                weighDates: weighDates,
                onSelect: (d) => setState(() => _selected = d),
                onPrev: () => _shiftWeek(-1),
                onNext: () => _shiftWeek(1),
              ),
              // ② 本周摘要（3 个数字 + 看统计）
              WorkoutWeekSummary(summary: summary),
              // ③ 选中日明细
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      _sameDay(_selected, today)
                          ? '今天'
                          : DateFormat('M月d日 EEEE', 'zh_CN').format(_selected),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: dayWorkouts.isEmpty
                    // T17：选中某天无记录
                    ? _refreshable(WorkoutEmptyState(
                        icon: Icons.event_busy,
                        title: '这天没有训练',
                        subtitle: '换一天看看，或者现在就练一次',
                        buttonLabel: '现在去练一次',
                        onStart: () => context.go('/workout'),
                        secondaryLabel: '已练，记一笔',
                        onSecondary: () => context.push(
                            '/workout/log/new?date=${DateFormat('yyyy-MM-dd').format(_selected)}'),
                      ))
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(workoutHistoryProvider.future),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: dayWorkouts.length + 1,
                          itemBuilder: (_, i) {
                            // 列表末尾：当天已经有记录，但用户可能还练了别的没记，
                            // 给一个「记录不全，再记一笔」的补录入口。
                            if (i == dayWorkouts.length) {
                              return OutlinedButton.icon(
                                onPressed: () => context.push(
                                    '/workout/log/new?date=${DateFormat('yyyy-MM-dd').format(_selected)}'),
                                icon: const Icon(Icons.edit_note, size: 18),
                                label: const Text('记录不全，再记一笔'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  foregroundColor: AppColors.primaryText,
                                  side: const BorderSide(color: AppColors.border),
                                ),
                              );
                            }
                            return WorkoutRecordCard(
                              workout: dayWorkouts[i],
                              exerciseNames: exerciseNames,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
