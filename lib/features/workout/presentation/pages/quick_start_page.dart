import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';
import 'package:fittrack/features/workout/presentation/widgets/history_segment.dart';
import 'package:fittrack/features/workout/presentation/widgets/my_templates_section.dart';
import 'package:fittrack/features/workout/presentation/widgets/plan_segment.dart';
import 'package:fittrack/features/workout/presentation/widgets/recommended_section.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_filter_bar.dart';

/// 训练模板数据源（推荐模板 + 我的模板）
final workoutTemplatesProvider =
    FutureProvider<List<WorkoutTemplateEntity>>((ref) {
  return ref.watch(workoutTemplateRepoProvider).getAll();
});

/// 分类筛选的固定顺序（"全部"始终在最前）
const _focusOrder = <String>['全身', '放松', '碎片'];
const _allFocus = kAllFilter;

/// 训练页 —— 模板化开练（v3：Keep 课程列表风格，封面图优先）
class QuickStartPage extends ConsumerStatefulWidget {
  const QuickStartPage({super.key});

  @override
  ConsumerState<QuickStartPage> createState() => _QuickStartPageState();
}

class _QuickStartPageState extends ConsumerState<QuickStartPage> {
  bool _starting = false;

  /// 分段：0=计划 1=模板 2=历史
  int _segment = 1;

  /// 当前分类筛选（纯前端过滤已加载列表）
  String _focus = _allFocus;

  /// 难度筛选（固定三档，空档置灰不可点）
  String _difficulty = kAllFilter;

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
    } catch (e) {
      // 兜底：把异常展示给用户而不是红屏
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始训练失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// 依据推荐模板的 focus 生成分类 chips（"全部" + 存在数据的分类）
  List<String> _buildFilters(List<WorkoutTemplateEntity> recommended) {
    final existing = recommended.map((t) => t.focus).toSet();
    // 兜底：数据里出现未知 focus 时排在已知分类之后（按字典序）
    final unknown = existing.where((f) => !_focusOrder.contains(f)).toList()
      ..sort();
    return <String>[
      _allFocus,
      ..._focusOrder.where(existing.contains),
      ...unknown,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workoutTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建模板',
            onPressed: () => context.push('/workout/template-edit'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    label: Text('计划', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 1,
                    label: Text('模板', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 2,
                    label: Text('历史', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {_segment},
                onSelectionChanged: (s) => setState(() => _segment = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ),
          ),
          Expanded(
            child: switch (_segment) {
              0 => const PlanSegment(),
              2 => const HistorySegment(),
              _ => _buildTemplateView(async),
            },
          ),
        ],
      ),
    );
  }

  /// 模板分段（原页面主体：分类 + 推荐模板 + 我的模板）
  Widget _buildTemplateView(AsyncValue<List<WorkoutTemplateEntity>> async) {
    return async.when(
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
        final recommended = templates.where((t) => t.isRecommended).toList();
        final mine = templates.where((t) => !t.isRecommended).toList();
        final filters = _buildFilters(recommended);
        // 选中的分类在数据变化后可能已不存在 → 回落到 "全部"
        final active = filters.contains(_focus) ? _focus : _allFocus;
        // 场景 × 难度 AND 组合（纯函数，见 template_filter.dart）
        final visible = filterTemplates(recommended,
            focus: active, difficulty: _difficulty);
        // 各难度档在当前场景下的数量：为 0 的档位置灰（避免"点了没结果"）
        final diffs = difficultyCounts(recommended, focus: active);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // ── 分类 chips + 自定义入口 ──
            TemplateFilterBar(
              filters: filters,
              active: active,
              onSelect: (f) => setState(() => _focus = f),
              difficulty: _difficulty,
              difficultyCounts: diffs,
              onDifficulty: (d) => setState(() => _difficulty = d),
            ),

            const SizedBox(height: 18),

            // ── 我的模板（独立组件，默认 2 个 + 展开/收起）──
            MyTemplatesSection(
              templates: mine,
              starting: _starting,
              onStart: _startTemplate,
              onCreate: () => context.push('/workout/template-edit'),
              onEdit: (t) => context.push('/workout/template-edit?id=${t.id}'),
            ),

            const SizedBox(height: 18),

            // ── 推荐模板（独立组件管理展开状态，保证点击必生效）──
            RecommendedSection(
              templates: visible,
              starting: _starting,
              onStart: _startTemplate,
            ),
            // 底部留白由 ListView padding 的 bottom 24 承担
          ],
        );
      },
    );
  }
}

// ───────────────────── 分类 chips 行 ─────────────────────

/// 一行筛选：左侧小标题 + 横向滚动的 chips + 右侧可选动作

/// 难度 chip：描边样式，与场景组的实心 chip 视觉区分

// ───────────────────── 区段标题 ─────────────────────

// ───────────────────── 封面卡 ─────────────────────

/// Keep 风格的模板卡：封面图（渐变 + 大图标）优先，信息极简，整卡可点

/// 卡片封面：斜向渐变 + 中央大图标 + 装饰圆 + 角标（难度 / 时长 / 编辑）

// ───────────────────── 空态 / 提示 ─────────────────────

/// "我的模板"空态：紧凑卡（图标 + 文案 + 按钮）

/// 我的模板区（独立管理展开状态，默认显示 2 个）

/// 推荐模板区（独立管理展开状态，避免父级 async 闭包重建不生效）

/// 分类筛选后无内容的轻提示
