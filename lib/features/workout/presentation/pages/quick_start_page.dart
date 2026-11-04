import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';
import 'package:fittrack/features/workout/presentation/widgets/my_templates_section.dart';
import 'package:fittrack/features/workout/presentation/widgets/plan_segment.dart';
import 'package:fittrack/features/workout/presentation/widgets/recommended_section.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_filter_bar.dart';

/// 训练页（Tab）—— 只回答一个问题：**现在练什么**。
///
/// 拆分前这里是「计划 | 模板 | 历史」三段，而「历史」和记录页是**两份列表代码**，
/// 字段口径已经不一致（这里 N/M 组、记录页 N 组）。本期把记录搬到
/// `/workout/records`，历史分段整个删掉（决策 12）。
///
/// 明确不做（决策 9）：**没有时长选择器**（10/5/23 分钟）。"练多久"是第二个问题，
/// 提前到开练之前等于在"选内容"和"开始练"之间插一道选择题 —— 而模板卡上
/// 已经写了 12/15/20 分钟。也没有 FAB：新建模板走 AppBar 的 `+`。
class QuickStartPage extends ConsumerStatefulWidget {
  const QuickStartPage({super.key});

  @override
  ConsumerState<QuickStartPage> createState() => _QuickStartPageState();
}

class _QuickStartPageState extends ConsumerState<QuickStartPage> {
  bool _starting = false;

  /// 分段：0=计划 1=模板（**只有两段**，T2）
  int _segment = 1;

  /// 当前分类筛选（纯前端过滤已加载列表）
  String _type = kAllFilter;

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
      // 用 push 而不是 pushReplacement：pushReplacement 会把「训练页」这个
      // 底部 Tab 从栈里替换掉，练完按返回就直接掉到桌面（回不到训练页）。
      context.push('/workout/active', extra: slots);
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

  /// 删除一个推荐模板（内置模板也能删；删除前二次确认）
  Future<void> _deleteTemplate(WorkoutTemplateEntity template) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除推荐模板'),
        content: Text('确定要删除「${template.name}」吗？删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(workoutTemplateRepoProvider).delete(template.id);
    ref.invalidate(workoutTemplatesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workoutTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练'),
        centerTitle: false,
        actions: [
          // ① 训练记录（与「我的」里那个 tile 同为显性入口，都 push 同一路由）
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '训练记录',
            onPressed: () => context.push('/workout/records'),
          ),
          // ② 新建模板（原先靠 FAB，本期删 FAB，T4）
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
        // 类型（力量/有氧）× 难度 AND 组合（纯函数，见 template_filter.dart）。
        // 两个区**用同一套筛选**：之前只筛推荐、漏了「我的模板」（用户报修）。
        final visible =
            filterTemplates(recommended, type: _type, difficulty: _difficulty);
        final visibleMine =
            filterTemplates(mine, type: _type, difficulty: _difficulty);
        // 各难度档在当前类型下的数量：为 0 的档位置灰（避免"点了没结果"）。
        // 统计范围要和筛选范围一致 —— 用全量模板（推荐 + 我的），
        // 否则"只存在于我的模板里的难度"会被错误置灰。
        final diffs = difficultyCounts(templates, type: _type);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // ── 分类 chips + 自定义入口 ──
            TemplateFilterBar(
              type: _type,
              onType: (t) => setState(() => _type = t),
              difficulty: _difficulty,
              difficultyCounts: diffs,
              onDifficulty: (d) => setState(() => _difficulty = d),
            ),

            const SizedBox(height: 18),

            // ── 我的模板（独立组件，默认 2 个 + 展开/收起）──
            MyTemplatesSection(
              templates: visibleMine,
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
              onDelete: _deleteTemplate,
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
