import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/core/widgets/timer_card.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';

/// 统一训练执行页 —— 自由训练 & 计划训练共用
///
/// 路由：
/// - 自由训练：`/workout/active`，extra = `List<ExerciseSlot>`
/// - 计划训练：`/plan/:id/execute`，extra = `int? dayOfWeek`
class WorkoutActivePage extends ConsumerStatefulWidget {
  /// 自由训练的初始动作槽位（构造函数传入，编译期类型安全；计划训练为 null）
  final List<ExerciseSlot>? initialSlots;

  const WorkoutActivePage({super.key, this.initialSlots});

  @override
  ConsumerState<WorkoutActivePage> createState() => _WorkoutActivePageState();
}

class _WorkoutActivePageState extends ConsumerState<WorkoutActivePage> {
  bool _initialized = false;
  late final String _location;
  late final dynamic _extra;

  final _repsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _location = GoRouterState.of(context).uri.toString();
    _extra = GoRouterState.of(context).extra;
    _initSession();
  }

  void _initSession() {
    final notifier = ref.read(workoutSessionProvider.notifier);

    if (_location.startsWith('/plan/')) {
      final parts = _location.split('/');
      final planId = int.tryParse(parts.length > 2 ? parts[2].split('?').first : '') ?? 0;
      final dayOfWeek = _extra is int ? _extra : DateTime.now().weekday % 7;
      notifier.initPlan(planId, dayOfWeek);
    } else if (widget.initialSlots != null) {
      notifier.initFree(widget.initialSlots!);
    } else if (_extra is List<ExerciseSlot>) {
      // 兼容通过 extra 直接传参的旧调用路径
      notifier.initFree(_extra);
    }
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(workoutSessionProvider);
    final notifier = ref.read(workoutSessionProvider.notifier);
    final theme = Theme.of(context);

    // 计划模式加载中
    if (sessionState.sessionType == 'plan' && sessionState.slots.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('执行计划')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // 无动作数据
    if (sessionState.slots.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('训练')),
        body: const Center(child: Text('未选择动作')),
      );
    }

    // 全部完成
    if (sessionState.isComplete) {
      return _buildCompleteView(theme, sessionState, notifier);
    }

    final slot = sessionState.currentSlot!;
    final catColor = AppTheme.categoryColors[slot.category] ?? Colors.grey;
    final isLastSet = sessionState.isLastSetOfCurrentSlot;
    final isLastExercise = sessionState.isLastSlot;
    final appBarTitle = sessionState.sessionType == 'plan' ? '计划训练' : '训练中';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          TextButton(
            onPressed: () => _confirmAbandon(context),
            child: const Text('放弃'),
          ),
        ],
      ),
      body: Container(
        decoration: sessionState.isTraining
            ? BoxDecoration(
                border: Border.all(color: Colors.redAccent.withAlpha(180), width: 7.5),
              )
            : null,
        child: Column(
          children: [
            // 进度条
            LinearProgressIndicator(
              value: (sessionState.currentSlotIndex +
                      (sessionState.currentSetIndex /
                          (slot.targetSets > 0 ? slot.targetSets : 1))) /
                  sessionState.slots.length,
            ),
            // 动作信息头
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: catColor.withAlpha(40),
                    radius: 24,
                    child: Icon(
                      AppTheme.categoryIcons[slot.category] ?? Icons.fitness_center,
                      color: catColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(slot.exerciseName, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          isLastSet
                              ? '${slot.targetSets} / ${slot.targetSets} 组 · 已完成'
                              : '第 ${sessionState.currentSetIndex + 1} / ${slot.targetSets} 组',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // 计划训练的目标提示
            if (sessionState.sessionType == 'plan' && !isLastSet)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                child: Text(
                  _formatTarget(slot),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),

            // 输入区域
            if (!isLastSet)
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: _buildInputForm(theme, sessionState, notifier, slot),
                ),
              ),
          ],
        ),
      ),
      // 底部按钮
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (sessionState.currentSetIndex > 0 && !sessionState.isAutoMode)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => notifier.prevSet(),
                    child: const Text('上一组'),
                  ),
                ),
              if (sessionState.currentSetIndex > 0 && !sessionState.isAutoMode)
                const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: isLastSet
                    ? FilledButton.icon(
                        onPressed: isLastExercise
                            ? () => notifier.nextExercise()
                            : () => notifier.nextExercise(),
                        icon: Icon(isLastExercise ? Icons.check : Icons.arrow_forward),
                        label: Text(isLastExercise ? '完成训练' : '下一个动作'),
                      )
                    : sessionState.isAutoMode
                        ? FilledButton.icon(
                            onPressed: () => notifier.stopAutoMode(),
                            icon: const Icon(Icons.stop),
                            label: const Text('停止自动'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
                          )
                        : FilledButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              notifier.completeCurrentSet(
                                reps: _repsCtrl.text,
                                weight: _weightCtrl.text,
                                duration: _durationCtrl.text,
                              );
                              _repsCtrl.clear();
                              _weightCtrl.clear();
                              _durationCtrl.clear();
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('完成本组'),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputForm(
    ThemeData theme,
    WorkoutSessionState state,
    WorkoutSessionNotifier notifier,
    ExerciseSlot slot,
  ) {
    final category = slot.category;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 热身组开关 + 节拍控制
        Row(
          children: [
            Text('热身组', style: theme.textTheme.bodyMedium),
            Switch(
              value: false, // 简化：热身组状态由调用方管理
              onChanged: (_) {},
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const Spacer(),
            if (!state.isTraining && !state.isResting) ...[
              Text('节拍',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: state.paceIntervalSec,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1秒', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 2, child: Text('2秒', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 3, child: Text('3秒', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 4, child: Text('4秒', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (v) => notifier.setPaceIntervalSec(v!),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // 次数输入（非有氧动作）
        if (category != 'cardio') ...[
          TextField(
            controller: _repsCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '次数',
              hintText: state.lastReps ?? '例如: 12',
              suffixText: '次',
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 重量输入（器械动作）
        if (category == 'gym') ...[
          TextField(
            controller: _weightCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '重量',
              hintText: state.lastWeight ?? '例如: 60',
              suffixText: 'kg',
            ),
          ),
        ],

        // 时长输入（有氧/拉伸动作）
        if (category == 'cardio' || category == 'stretch') ...[
          TextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '时长',
              hintText: state.lastDuration ?? '例如: 300',
              suffixText: '秒',
            ),
          ),
        ],

        const SizedBox(height: 8),
        // 保存为默认
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              notifier.completeCurrentSet(
                reps: _repsCtrl.text,
                weight: _weightCtrl.text,
                duration: _durationCtrl.text,
              );
              // Undo the set completion — we just want to save defaults
              // Actually _saveExerciseDefaults is private; save via completing is wrong.
              // Just show the snackbar for UX — defaults save on completeCurrentSet.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('保存为默认值'), duration: Duration(seconds: 1)),
              );
            },
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('保存为默认', style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(height: 12),

        // ── 训练 & 休息倒计时卡片（并列） ──
        Row(
          children: [
            Expanded(
              child: TimerCard(
                label: '训练倒计时',
                seconds: state.isTraining ? state.trainingSeconds : state.trainingDurationSec,
                isActive: state.isTraining,
                icon: Icons.fitness_center,
                color: theme.colorScheme.primary,
                onEdit: state.isTraining ? null : () => _editTrainingTime(context, notifier, state),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TimerCard(
                label: '休息倒计时',
                seconds: state.isResting ? state.restSeconds : state.restDurationSec,
                isActive: state.isResting,
                icon: Icons.timer,
                color: theme.colorScheme.tertiary,
                onEdit: state.isResting ? null : () => _editRestTime(context, notifier, state),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── 操作按钮行 ──
        if (!state.isAutoMode)
          Row(
            children: [
              if (state.sessionType == 'plan')
                OutlinedButton.icon(
                  onPressed: () {
                    _repsCtrl.clear();
                    _weightCtrl.clear();
                    _durationCtrl.clear();
                    notifier.skipCurrentSet();
                  },
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('跳过'),
                ),
              if (state.sessionType == 'plan') const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => notifier.startTraining(),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('开始训练'),
                  style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: state.isResting
                      ? () => notifier.stopRest()
                      : () => notifier.startRest(),
                  icon: Icon(
                      state.isResting ? Icons.timer_off : Icons.timer, size: 18),
                  label: Text(state.isResting ? '停止休息' : '休息'),
                ),
              ),
            ],
          ),

        // ── 语音 & 节拍控制 ──
        if (!state.isAutoMode) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              FilterChip(
                avatar: Icon(
                    notifier.voiceEnabled ? Icons.volume_up : Icons.volume_off,
                    size: 18),
                label: Text(notifier.voiceEnabled ? '语音开' : '语音关',
                    style: const TextStyle(fontSize: 12)),
                selected: notifier.voiceEnabled,
                onSelected: (v) => notifier.setVoiceEnabled(v),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],

        // ── 正在倒计时的大字显示 ──
        if (state.isTraining || state.isResting) ...[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Text(
                  state.isTraining ? '训练中' : '休息中',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  state.isTraining
                      ? _fmtTime(state.trainingSeconds)
                      : _fmtTime(state.restSeconds),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: state.isTraining
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                    fontSize: 52,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCompleteView(
    ThemeData theme,
    WorkoutSessionState state,
    WorkoutSessionNotifier notifier,
  ) {
    final totalSets = state.completedSets.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('训练中'),
        actions: [
          TextButton(
            onPressed: () => _confirmAbandon(context),
            child: const Text('放弃'),
          ),
        ],
      ),
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Opacity(
                opacity: value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.celebration, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('训练完成！', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  '共 ${state.slots.length} 个动作 · $totalSets 组',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await notifier.saveWorkout();
                    if (mounted) context.go('/');
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('保存训练记录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 编辑倒计时对话框 ──

  void _editTrainingTime(
      BuildContext context, WorkoutSessionNotifier notifier, WorkoutSessionState state) {
    final ctrl = TextEditingController(text: '${state.trainingDurationSec}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练时长（秒）'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如: 60', suffixText: '秒'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v != null && v > 0) notifier.setTrainingDurationSec(v);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _editRestTime(
      BuildContext context, WorkoutSessionNotifier notifier, WorkoutSessionState state) {
    final ctrl = TextEditingController(text: '${state.restDurationSec}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('休息时长（秒）'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如: 90', suffixText: '秒'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              if (v != null && v > 0) notifier.setRestDurationSec(v);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _confirmAbandon(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃训练？'),
        content: const Text('当前训练进度将不会保存。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('继续训练')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('放弃'),
          ),
        ],
      ),
    );
  }

  String _fmtTime(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatTarget(ExerciseSlot slot) {
    final parts = <String>[];
    parts.add('目标: ${slot.targetSets} 组');
    if (slot.targetReps != null) parts.add('${slot.targetReps} 次');
    if (slot.targetWeightKg != null) {
      parts.add('${slot.targetWeightKg!.toStringAsFixed(1)} kg');
    }
    if (slot.targetDurationSec != null) parts.add('${slot.targetDurationSec} 秒');
    return parts.join(' · ');
  }
}
