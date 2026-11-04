import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/route_query.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/workout_log_draft.dart';
import 'package:fittrack/features/workout/presentation/widgets/exercise_picker_sheet.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_log_entry_row.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_log_template_picker.dart';

/// 「记一笔」—— 纯记录模块：**训练不在 App 里做，事后照着模板记一遍**。
///
/// 与「开练」是两条完全不同的路，所以刻意不共用界面：
/// - 开练：边练边记（计时、休息、逐组完成）
/// - 记一笔：练完回忆（选模板 → 带出动作 → 填实际组次重 → 保存）
///
/// 三个刻意的决定：
/// 1. **必须先选模板**（没有"空白模式"）。空白模式等于让用户从动作库手搓一遍，
///    那不是记录，是录入考试；而模板本来就是"我常练的那几套"。
/// 2. **不带重量**：模板里没有重量字段，"帮用户填好"会让补记变成假数据。
/// 3. 保存走 `WorkoutRepository.createWorkout`（与开练**同一条写入路径**）：
///    第二套写入逻辑迟早会在 `isCompleted` / `setNumber` 这些细节上和它分叉。
class WorkoutLogPage extends ConsumerStatefulWidget {
  const WorkoutLogPage({super.key});

  @override
  ConsumerState<WorkoutLogPage> createState() => _WorkoutLogPageState();
}

class _WorkoutLogPageState extends ConsumerState<WorkoutLogPage> {
  /// 选中的模板；null = 还在选模板这一步
  WorkoutTemplateEntity? _template;
  WorkoutLogDraft _draft = const WorkoutLogDraft();
  bool _saving = false;

  /// 补记的日期：来自记录页选中的那天（?date=），默认今天
  late DateTime _date = DateTime.now();
  bool _dateRead = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dateRead) return;
    _dateRead = true;
    final raw = routeQueryParam(context, 'date');
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    _date = parsed ?? DateTime.now();
  }

  void _chooseTemplate(WorkoutTemplateEntity template) {
    setState(() {
      _template = template;
      _draft = WorkoutLogDraft.fromTemplate(template);
    });
  }

  /// 回到模板列表（已填的内容会丢，所以要二次确认）
  Future<void> _backToTemplates() async {
    if (_draft.isEmpty) {
      setState(() => _template = null);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('换一个模板？'),
        content: const Text('已经填的内容会清空。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('换模板')),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        _template = null;
        _draft = const WorkoutLogDraft();
      });
    }
  }

  Future<void> _addExercise() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.82,
        child: ExercisePickerSheet(
          onPick: (exercise) {
            Navigator.pop(sheetContext);
            if (_draft.contains(exercise.id)) {
              _toast('这个动作已经在清单里了');
              return;
            }
            setState(() {
              _draft = _draft.add(WorkoutLogEntry.fromExercise(
                exerciseId: exercise.id,
                exerciseName: exercise.name,
                category: exercise.category,
                defaultReps: exercise.defaultReps,
                defaultDurationSec: exercise.defaultDurationSec,
              ));
            });
          },
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_draft.canSave) return;
    setState(() => _saving = true);
    try {
      await ref.read(workoutRepoProvider).createWorkout(
            date: _date,
            // type 固定 free：它就是"不是计划里的训练"。planId 留 null ⇒
            // 天然不进计划完成度，只进统计（次数/时长/图表）。
            type: WorkoutLogDraft.workoutType,
            planId: null,
            // note 不写：那是用户写"今天膝盖有点疼"的地方，留给用户
            sets: _draft.toSets(),
          );

      // 复用「保存训练」的既有刷新入口（与开练流程逐条一致，别另造一套）
      ref.invalidate(workoutHistoryProvider);
      ref.invalidate(dashboardDataProvider);
      ref.invalidate(trendsDataProvider);
      ref.invalidate(goalListProvider);

      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (mounted) _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final choosing = _template == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(choosing ? '记一笔 · 选模板' : '记一笔'),
        centerTitle: false,
        actions: [
          if (!choosing)
            TextButton(
              onPressed: _backToTemplates,
              child: const Text('换模板'),
            ),
        ],
      ),
      body: choosing
          ? WorkoutLogTemplatePicker(onPick: _chooseTemplate)
          : _buildForm(),
      bottomNavigationBar: choosing ? null : _buildSaveBar(),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      children: [
        Row(
          children: [
            const Icon(Icons.assignment_outlined,
                size: 16, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _template?.name ?? '',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '共 ${_draft.totalSets} 组',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '按实际做的填。没做的动作直接删掉，忘了重量就留自重。',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _draft.entries.length; i++)
          WorkoutLogEntryRow(
            key: ValueKey('log-entry-${_draft.entries[i].exerciseId}'),
            entry: _draft.entries[i],
            onChanged: (next) =>
                setState(() => _draft = _draft.replaceAt(i, next)),
            onDelete: () => setState(() => _draft = _draft.removeAt(i)),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _addExercise,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('加动作'),
        ),
        if (_draft.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              '这个模板没有动作？点上面「加动作」自己挑，或者回去换个模板。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }

  Widget _buildSaveBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            // 没有动作就不给保存：空记录没有任何信息量
            onPressed: _draft.canSave && !_saving ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(46),
            ),
            child: Text(_saving ? '保存中…' : '保存这一笔'),
          ),
        ),
      ),
    );
  }
}
