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

/// 分类筛选的固定顺序（"全部"始终在最前）
const _focusOrder = <String>['全身', '放松', '碎片'];
const _allFocus = '全部';

/// 训练页 —— 模板化开练（v3：Keep 课程列表风格，封面图优先）
class QuickStartPage extends ConsumerStatefulWidget {
  const QuickStartPage({super.key});

  @override
  ConsumerState<QuickStartPage> createState() => _QuickStartPageState();
}

class _QuickStartPageState extends ConsumerState<QuickStartPage> {
  bool _starting = false;

  /// 当前分类筛选（纯前端过滤已加载列表）
  String _focus = _allFocus;

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
          final recommended = templates.where((t) => t.isRecommended).toList();
          final mine = templates.where((t) => !t.isRecommended).toList();
          final filters = _buildFilters(recommended);
          // 选中的分类在数据变化后可能已不存在 → 回落到 "全部"
          final active = filters.contains(_focus) ? _focus : _allFocus;
          final visible = active == _allFocus
              ? recommended
              : recommended.where((t) => t.focus == active).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── 分类 chips + 自定义入口 ──
              _FilterBar(
                filters: filters,
                active: active,
                onSelect: (f) => setState(() => _focus = f),
              ),

              const SizedBox(height: 18),

              // ── 推荐模板 ──
              _SectionHeader(
                title: '推荐模板',
                trailing: '${visible.length} 个',
              ),
              const SizedBox(height: 10),
              if (visible.isEmpty)
                const _HintCard(text: '该分类下暂无模板，换个分类试试')
              else
                ...visible.map(
                  (t) => _TemplateCard(
                    template: t,
                    starting: _starting,
                    coverHeight: 132,
                    onStart: () => _startTemplate(t),
                  ),
                ),

              const SizedBox(height: 8),

              // ── 我的模板 ──
              _SectionHeader(
                title: '我的模板',
                trailingAction: TextButton.icon(
                  onPressed: () => context.push('/workout/template-edit'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: _green,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (mine.isEmpty)
                _EmptyMineCard(
                  onCreate: () => context.push('/workout/template-edit'),
                )
              else
                ...mine.map(
                  (t) => _TemplateCard(
                    template: t,
                    starting: _starting,
                    coverHeight: 92,
                    onStart: () => _startTemplate(t),
                    onEdit: () =>
                        context.push('/workout/template-edit?id=${t.id}'),
                  ),
                ),
              // 底部留白由 ListView padding 的 bottom 24 承担
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────── 分类 chips 行 ─────────────────────

class _FilterBar extends StatelessWidget {
  final List<String> filters;
  final String active;
  final ValueChanged<String> onSelect;

  const _FilterBar({
    required this.filters,
    required this.active,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FocusChip(
                        label: f,
                        selected: f == active,
                        onTap: () => onSelect(f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 34,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/workout/custom'),
              icon: const Icon(Icons.tune, size: 14),
              label: const Text('自定义',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: Colors.white.withAlpha(38)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FocusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _green.withAlpha(28) : Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? _green : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? _green : Colors.white70,
          ),
        ),
      ),
    );
  }
}

// ───────────────────── 区段标题 ─────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? trailingAction;

  const _SectionHeader({
    required this.title,
    this.trailing,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const Spacer(),
        if (trailingAction != null)
          trailingAction!
        else if (trailing != null)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              trailing!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

// ───────────────────── 封面卡 ─────────────────────

/// Keep 风格的模板卡：封面图（渐变 + 大图标）优先，信息极简，整卡可点
class _TemplateCard extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final bool starting;
  final double coverHeight;
  final VoidCallback onStart;
  final VoidCallback? onEdit;

  const _TemplateCard({
    required this.template,
    required this.starting,
    required this.coverHeight,
    required this.onStart,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: starting ? null : onStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TemplateCover(
              template: template,
              height: coverHeight,
              compact: coverHeight < 120,
              onEdit: onEdit,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.items.length} 个动作 · ${template.focus}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: _green.withAlpha(60),
                    disabledForegroundColor: Colors.black54,
                    elevation: 0,
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: starting ? null : onStart,
                  child: const Text('开始训练'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卡片封面：斜向渐变 + 中央大图标 + 装饰圆 + 角标（难度 / 时长 / 编辑）
class _TemplateCover extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final double height;
  final bool compact;
  final VoidCallback? onEdit;

  const _TemplateCover({
    required this.template,
    required this.height,
    required this.compact,
    this.onEdit,
  });

  /// accentKey → 渐变双色（深色收尾，保证白字可读）
  static const _gradients = <String, List<Color>>{
    'green': [Color(0xFF66BB6A), Color(0xFF1B5E20)],
    'orange': [Color(0xFFFF7043), Color(0xFFBF360C)],
    'red': [Color(0xFFEF5350), Color(0xFFB71C1C)],
    'cyan': [Color(0xFF26C6DA), Color(0xFF00695C)],
    'purple': [Color(0xFFAB47BC), Color(0xFF4A148C)],
  };

  static const _icons = <String, IconData>{
    'green': Icons.fitness_center,
    'orange': Icons.local_fire_department,
    'red': Icons.bolt,
    'cyan': Icons.business_center,
    'purple': Icons.nightlight_round,
  };

  static const List<Color> _fallback = [Color(0xFF66BB6A), Color(0xFF1B5E20)];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[template.accentKey] ?? _fallback;
    final icon = _icons[template.accentKey] ?? Icons.fitness_center;
    final iconSize = compact ? 32.0 : 46.0;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 渐变底
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
          // 装饰圆：制造层次，避免纯色块
          Positioned(
            right: -18,
            top: -26,
            child: _DecorCircle(size: compact ? 74 : 104),
          ),
          Positioned(
            left: -14,
            bottom: -30,
            child: _DecorCircle(size: compact ? 58 : 84),
          ),
          Positioned(
            right: compact ? 42 : 68,
            bottom: compact ? 10 : 18,
            child: _DecorCircle(size: compact ? 24 : 34),
          ),
          // 中央动作图标
          Center(
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withAlpha(200),
            ),
          ),
          // 左上：难度
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                template.difficulty,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          // 右上：编辑按钮（我的模板）或时长（推荐模板）
          if (onEdit != null)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black.withAlpha(46),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEdit,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.edit_note,
                        size: 18, color: Colors.white),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 10,
              top: 11,
              child: Text(
                '${template.minutes} 分钟',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(230),
                ),
              ),
            ),
          // 编辑按钮占用了右上角时，时长落到封面右下
          if (onEdit != null)
            Positioned(
              right: 12,
              bottom: 8,
              child: Text(
                '${template.minutes} 分钟',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(230),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  final double size;

  const _DecorCircle({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(18),
      ),
    );
  }
}

// ───────────────────── 空态 / 提示 ─────────────────────

/// "我的模板"空态：紧凑卡（图标 + 文案 + 按钮）
class _EmptyMineCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyMineCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCreate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bookmark_add_outlined,
                    size: 22, color: Colors.white38),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '创建你的第一个组合',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '把常做的动作存成模板，一键开练',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: onCreate,
                  child: const Text('新建'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分类筛选后无内容的轻提示
class _HintCard extends StatelessWidget {
  final String text;

  const _HintCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: Center(
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
