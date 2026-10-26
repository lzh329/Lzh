import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/features/workout/presentation/notifiers/workout_session_notifier.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_action_card.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_complete_view.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_entry_panel.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_footer.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_header.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_placeholder.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_style.dart';
import 'package:fittrack/features/workout/presentation/widgets/active_workout_tool_row.dart';

/// 统一训练执行页 —— 自由训练 & 计划训练共用
///
/// 布局（Keep「训练中」风格）：
/// 顶部自定义头部 → 中部动作大卡片（占屏约一半）→ 紧凑输入区 + 工具行
/// → 底部固定操作区。
///
/// 路由：
/// - 自由训练：`/workout/active`，extra = `List<ExerciseSlot>`
/// - 计划训练：`/plan/:id/execute`，extra = `int? dayOfWeek`
///
/// 本文件只负责布局与状态分支编排；计时、组次记录、休息倒计时、语音播报、
/// 保存训练等业务逻辑全部委托给 [WorkoutSessionNotifier]，未作改动。
class WorkoutActivePage extends ConsumerStatefulWidget {
  /// 自由训练的初始动作槽位（构造函数传入，编译期类型安全；计划训练为 null）
  final List<ExerciseSlot>? initialSlots;

  const WorkoutActivePage({super.key, this.initialSlots});

  @override
  ConsumerState<WorkoutActivePage> createState() => _WorkoutActivePageState();
}

class _WorkoutActivePageState extends ConsumerState<WorkoutActivePage>
    with WidgetsBindingObserver {
  bool _initialized = false;
  bool _sessionReady = false;
  late final String _location;
  late final dynamic _extra;

  final _repsCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();

  /// 提前持有 notifier：dispose 里还要用它清掉计时与语音
  late final WorkoutSessionNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(workoutSessionProvider.notifier);
    WidgetsBinding.instance.addObserver(this);
    // 训练期间保持屏幕常亮：锁屏/省电不会冻结倒计时，看动作也方便
    WakelockPlus.enable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 切后台 / 回桌面：暂停倒计时并静音，避免在桌面上继续念数字
        _notifier.pauseForBackground();
      case AppLifecycleState.resumed:
        _notifier.resumeFromBackground();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _location = GoRouterState.of(context).uri.toString();
    _extra = GoRouterState.of(context).extra;

    // Riverpod 禁止在 widget 生命周期内修改 provider：
    // 延后到当前帧构建完成后再初始化训练会话
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initSession();
      setState(() => _sessionReady = true);
    });
  }

  void _initSession() {
    final notifier = ref.read(workoutSessionProvider.notifier);

    Future<void> init;
    if (_location.startsWith('/plan/')) {
      final parts = _location.split('/');
      final planId =
          int.tryParse(parts.length > 2 ? parts[2].split('?').first : '') ?? 0;
      final dayOfWeek = _extra is int ? _extra : DateTime.now().weekday % 7;
      init = notifier.initPlan(planId, dayOfWeek);
    } else if (widget.initialSlots != null) {
      notifier.initFree(widget.initialSlots!);
      init = Future.value();
    } else if (_extra is List<ExerciseSlot>) {
      // 兼容通过 extra 直接传参的旧调用路径
      notifier.initFree(_extra);
      init = Future.value();
    } else {
      init = Future.value();
    }

    // 计时类动作：进入执行页直接开始倒计时
    init.then((_) {
      if (!mounted) return;
      final s = ref.read(workoutSessionProvider);
      final slot = s.currentSlot;
      if (slot == null) return;
      final isTimed = slot.category == 'cardio' ||
          slot.category == 'stretch' ||
          slot.targetDurationSec != null;
      if (isTimed) notifier.startTraining();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    // 离开训练页：停掉倒计时与语音队列（否则退出后仍在念数字）
    _notifier.stopAllTimersAndVoice();
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  // ──────────────────────────── 构建 ────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessionState = ref.watch(workoutSessionProvider);
    final notifier = ref.read(workoutSessionProvider.notifier);

    // 分支 1：会话初始化中（provider 修改已延后到帧后执行，避免空态闪烁）
    if (!_sessionReady) {
      return ActiveWorkoutPlaceholder(
        label: '训练',
        onClose: () => _confirmAbandon(context),
      );
    }

    // 分支 2：计划模式加载中
    if (sessionState.sessionType == 'plan' && sessionState.slots.isEmpty) {
      return ActiveWorkoutPlaceholder(
        label: '执行计划',
        onClose: () => _confirmAbandon(context),
      );
    }

    // 分支 3：无动作数据
    if (sessionState.slots.isEmpty) {
      return ActiveWorkoutPlaceholder(
        label: '未选择动作',
        isLoading: false,
        onClose: () => Navigator.of(context).maybePop(),
        closeTooltip: '返回',
      );
    }

    // 分支 4：全部完成
    if (sessionState.isComplete) {
      return ActiveWorkoutCompleteView(
        exerciseCount: sessionState.slots.length,
        setCount: sessionState.completedSets.length,
        onSave: () => _saveWorkoutAndExit(notifier),
        onClose: () => _confirmAbandon(context),
      );
    }

    // 分支 5：训练进行中
    final slot = sessionState.currentSlot!;
    final isLastSet = sessionState.isLastSetOfCurrentSlot;
    final isTimed =
        _isTimedCategory(slot.category) || slot.targetDurationSec != null;
    final nextSlot =
        sessionState.currentSlotIndex + 1 < sessionState.slots.length
            ? sessionState.slots[sessionState.currentSlotIndex + 1]
            : null;

    return Scaffold(
      backgroundColor: ActiveWorkoutStyle.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ActiveWorkoutHeader(
              currentIndex: sessionState.currentSlotIndex,
              total: sessionState.slots.length,
              progress: _overallProgress(sessionState, slot),
              roundText:
                  '第 ${sessionState.currentRound} 轮 / 共 ${sessionState.totalRounds} 轮 · 动作 ${sessionState.currentSlotIndex + 1}/${sessionState.slots.length}',
              onClose: () => _confirmAbandon(context),
              onSettings: () => _showSettingsSheet(notifier),
            ),
            const SizedBox(height: ActiveWorkoutStyle.gapSection),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // 中部主区：动作大卡片（占屏约 50%，键盘弹出时可滚动）
                    SizedBox(
                      height: _cardHeight(context),
                      child: ActiveWorkoutActionCard(
                        exerciseName: slot.exerciseName,
                        targetText: _targetText(slot),
                        statusText: _statusText(sessionState, slot, isLastSet),
                        isResting: sessionState.isResting,
                        isTraining: sessionState.isTraining,
                        isLastSet: isLastSet,
                        isTimed: isTimed,
                        targetReps: slot.targetReps,
                        displaySeconds:
                            _displaySeconds(sessionState, slot, isTimed),
                        restTotalSec: sessionState.restDurationSec,
                        onSkipRest: () => notifier.stopRest(),
                      ),
                    ),
                    if (nextSlot != null) ...[
                      const SizedBox(height: 8),
                      _buildNextHint(nextSlot.exerciseName),
                    ],
                    // 计时类动作（平板支撑 / 拉伸 / 有氧）不做手动输入：
                    // 倒计时自动开始，组次与时长在右上角 ⚙ 训练设置里调整
                    if (!isTimed) ...[
                      const SizedBox(height: ActiveWorkoutStyle.gapBlock),
                      ActiveWorkoutEntryPanel(
                        category: slot.category,
                        isTimed: isTimed,
                        isResting: sessionState.isResting,
                        isLastSet: isLastSet,
                        lastReps: sessionState.lastReps,
                        lastWeight: sessionState.lastWeight,
                        lastDuration: sessionState.lastDuration,
                        targetReps: slot.targetReps,
                        targetDurationSec: slot.targetDurationSec,
                        targetWeightKg: slot.targetWeightKg,
                        repsController: _repsCtrl,
                        weightController: _weightCtrl,
                        durationController: _durationCtrl,
                      ),
                      const SizedBox(height: ActiveWorkoutStyle.gapBlock),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ActiveWorkoutStyle.gapBlock,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 12,
                              color: ActiveWorkoutStyle.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '倒计时自动开始 · 时长可在右上角 ⚙ 调整',
                              style: TextStyle(
                                fontSize: 11,
                                color: ActiveWorkoutStyle.textTertiary
                                    .withAlpha(200),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // 底部固定操作区
      bottomNavigationBar: ActiveWorkoutFooter(
        primaryLabel: _primaryLabel(sessionState, isLastSet),
        primaryIcon: _primaryIcon(sessionState, isLastSet),
        primaryColor: _primaryColor(sessionState),
        onPrimary: () => _onPrimaryTap(sessionState, notifier, isLastSet),
        canSkipExercise: !sessionState.isAutoMode,
        onSkipExercise: () => _skipExercise(notifier),
        onFinishWorkout: () => _confirmAbandon(context),
      ),
    );
  }

  /// 卡片下方的「下一个动作」提示
  Widget _buildNextHint(String nextExerciseName) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '下一个：$nextExerciseName',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.5,
          color: ActiveWorkoutStyle.textTertiary,
        ),
      ),
    );
  }

  /// 通用「秒数」编辑弹窗
  void _editSeconds(
    BuildContext context,
    String title,
    int current,
    ValueChanged<int> onSave,
  ) {
    final ctrl = TextEditingController(text: '$current');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: '例如: 30', suffixText: '秒'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入大于 0 的秒数')),
                );
                return;
              }
              onSave(v);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// 训练设置弹层（把计时 / 休息 / 节拍 / 语音等次级控制从主界面收走）
  void _showSettingsSheet(WorkoutSessionNotifier notifier) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final s = ref.watch(workoutSessionProvider);
          final slot = s.currentSlot;
          final isTimed = slot != null &&
              (_isTimedCategory(slot.category) ||
                  slot.targetDurationSec != null);
          final actionDuration =
              slot?.targetDurationSec ?? s.trainingDurationSec;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '训练设置',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '计时 · 休息 · 节拍 · 语音',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 14),
                  // 计时类动作：本动作时长（不在主界面放输入框，统一在这里改）
                  if (isTimed) ...[
                    _TimeCard(
                      label: '本动作时长 · ${slot.exerciseName}',
                      value: '$actionDuration',
                      unit: '秒',
                      onTap: () => _editSeconds(
                        context,
                        '${slot.exerciseName} 时长（秒）',
                        actionDuration,
                        (v) => notifier.setCurrentSlotDurationSec(v),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  // 大号时间设置（本次重构重点）
                  Row(
                    children: [
                      Expanded(
                        child: _TimeCard(
                          label: '动作间休息',
                          value: '${s.restShortSec}',
                          unit: '秒',
                          onTap: () => _editSeconds(
                            context,
                            '动作间休息（秒）',
                            s.restShortSec,
                            (v) => notifier.setRestShortSec(v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeCard(
                          label: '轮间休息',
                          value: '${s.restLongSec}',
                          unit: '秒',
                          onTap: () => _editSeconds(
                            context,
                            '轮间休息（秒）',
                            s.restLongSec,
                            (v) => notifier.setRestLongSec(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _TimeCard(
                    label: '计时动作默认时长（未单独设置的动作）',
                    value: '${s.trainingDurationSec}',
                    unit: '秒',
                    onTap: () => _editSeconds(
                      context,
                      '计时动作默认时长（秒）',
                      s.trainingDurationSec,
                      (v) => notifier.setTrainingDurationSec(v),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildToolRow(s, notifier),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 工具行（次级控制，保留原有节拍 / 语音 / 时长设置 / 休息开关等入口）
  Widget _buildToolRow(
    WorkoutSessionState state,
    WorkoutSessionNotifier notifier,
  ) {
    return ActiveWorkoutToolRow(
      showPrevSet: state.currentSetIndex > 0,
      isAutoMode: state.isAutoMode,
      isResting: state.isResting,
      voiceEnabled: notifier.voiceEnabled,
      restDurationSec: state.restDurationSec,
      trainingDurationSec: state.trainingDurationSec,
      paceIntervalSec: state.paceIntervalSec,
      onPrevSet: () => notifier.prevSet(),
      onStartTraining: () {
        HapticFeedback.selectionClick();
        notifier.startTraining();
      },
      onStopTimer: () => notifier.stopAutoMode(),
      onToggleRest: () {
        if (state.isResting) {
          notifier.stopRest();
        } else {
          notifier.startRest();
        }
      },
      onEditTrainingTime: () => _editTrainingTime(notifier, state),
      onEditRestTime: () => _editRestTime(notifier, state),
      onCyclePace: () {
        final next = state.paceIntervalSec >= 4 ? 1 : state.paceIntervalSec + 1;
        notifier.setPaceIntervalSec(next);
      },
      onToggleVoice: () => notifier.setVoiceEnabled(!notifier.voiceEnabled),
    );
  }

  // ──────────────────── 状态 -> 主按钮映射 ────────────────────

  String _primaryLabel(WorkoutSessionState state, bool isLastSet) {
    if (state.isResting) return '跳过休息';
    if (state.isAutoMode) return '停止计时';
    final isFinal = state.currentRound >= state.totalRounds && state.isLastSlot;
    return isFinal ? '完成训练' : '完成';
  }

  IconData _primaryIcon(WorkoutSessionState state, bool isLastSet) {
    if (state.isResting) return Icons.timer_off;
    if (state.isAutoMode) return Icons.stop;
    return Icons.check;
  }

  Color _primaryColor(WorkoutSessionState state) {
    if (state.isAutoMode && !state.isResting) return ActiveWorkoutStyle.orange;
    return ActiveWorkoutStyle.green;
  }

  void _onPrimaryTap(
    WorkoutSessionState state,
    WorkoutSessionNotifier notifier,
    bool isLastSet,
  ) {
    if (state.isResting) {
      notifier.stopRest();
      return;
    }
    if (state.isAutoMode) {
      notifier.stopAutoMode();
      return;
    }
    _completeCurrentSet(notifier);
  }

  /// 完成本组：沿用原有「读取输入 -> 记录 -> 清空 controller」流程
  void _completeCurrentSet(WorkoutSessionNotifier notifier) {
    HapticFeedback.lightImpact();
    notifier.completeCurrentSet(
      reps: _repsCtrl.text,
      weight: _weightCtrl.text,
      duration: _durationCtrl.text,
    );
    _repsCtrl.clear();
    _weightCtrl.clear();
    _durationCtrl.clear();
  }

  /// 跳过当前动作剩余组，直接进入下一个动作（复用 nextExercise）
  void _skipExercise(WorkoutSessionNotifier notifier) {
    _repsCtrl.clear();
    _weightCtrl.clear();
    _durationCtrl.clear();
    notifier.nextExercise();
  }

  /// 保存训练记录并回到首页（完成态）
  Future<void> _saveWorkoutAndExit(WorkoutSessionNotifier notifier) async {
    HapticFeedback.mediumImpact();
    await notifier.saveWorkout();
    if (mounted) context.go('/');
  }

  // ──────────────────────── 计算辅助 ────────────────────────

  /// 中部主区卡片高度：屏幕高度的 50%（限制在 180-420，约占屏 45-55%）
  double _cardHeight(BuildContext context) {
    final raw = MediaQuery.sizeOf(context).height * 0.5;
    if (!raw.isFinite) return 240;
    return raw.clamp(180.0, 420.0);
  }

  bool _isTimedCategory(String category) {
    return category == 'cardio' || category == 'stretch';
  }

  /// 整体进度（沿用原有算法：已完成动作数 + 当前动作组内进度）
  double _overallProgress(WorkoutSessionState state, ExerciseSlot slot) {
    if (state.slots.isEmpty) return 0;
    final perSlot = slot.targetSets > 0 ? slot.targetSets : 1;
    final raw = (state.currentSlotIndex + state.currentSetIndex / perSlot) /
        state.slots.length;
    if (!raw.isFinite) return 0;
    return raw.clamp(0.0, 1.0);
  }

  /// 大卡片状态文案
  String _statusText(
    WorkoutSessionState state,
    ExerciseSlot slot,
    bool isLastSet,
  ) {
    if (state.isResting) return '休息中';
    if (state.isTraining) return '训练中';
    return '第 ${state.currentRound} 轮 / 共 ${state.totalRounds} 轮';
  }

  /// 大卡片中部大字所用秒数
  int _displaySeconds(
    WorkoutSessionState state,
    ExerciseSlot slot,
    bool isTimed,
  ) {
    if (state.isResting) return state.restSeconds;
    if (state.isTraining) return state.trainingSeconds;
    if (isTimed) return slot.targetDurationSec ?? state.trainingDurationSec;
    return 0;
  }

  /// 目标文案：`3 组 × 15 次` / `3 组 × 30 秒`（可附加目标重量）
  String _targetText(ExerciseSlot slot) {
    final buffer = StringBuffer('${slot.targetSets} 组');
    if (slot.targetReps != null) {
      buffer.write(' × ${slot.targetReps} 次');
    } else if (slot.targetDurationSec != null) {
      buffer.write(' × ${slot.targetDurationSec} 秒');
    }
    if (slot.targetWeightKg != null) {
      buffer.write(' · ${_formatWeight(slot.targetWeightKg!)} kg');
    }
    return buffer.toString();
  }

  String _formatWeight(double weightKg) {
    return weightKg % 1 == 0
        ? weightKg.toStringAsFixed(0)
        : weightKg.toStringAsFixed(1);
  }

  // ──────────────────────── 对话框 ────────────────────────

  /// 编辑训练时长
  void _editTrainingTime(
    WorkoutSessionNotifier notifier,
    WorkoutSessionState state,
  ) {
    final ctrl = TextEditingController(text: '${state.trainingDurationSec}');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('训练时长（秒）'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: '例如: 60', suffixText: '秒'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) {
                // 非法输入：不关闭弹窗，给出明确提示
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入大于 0 的秒数')),
                );
                return;
              }
              notifier.setTrainingDurationSec(v);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// 编辑休息时长
  void _editRestTime(
    WorkoutSessionNotifier notifier,
    WorkoutSessionState state,
  ) {
    final ctrl = TextEditingController(text: '${state.restDurationSec}');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('休息时长（秒）'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: '例如: 90', suffixText: '秒'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) {
                // 非法输入：不关闭弹窗，给出明确提示，让用户重新输入
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入大于 0 的秒数')),
                );
                return;
              }
              notifier.setRestDurationSec(v);
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  /// 确认退出训练
  void _confirmAbandon(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃训练？'),
        content: const Text('当前训练进度将不会保存。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('继续训练')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: AppColors.surface,
            ),
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
}

/// 训练设置弹层里的大号时间卡（显示 30px 数值 + 点击编辑）
class _TimeCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final VoidCallback onTap;

  const _TimeCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
  });

  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w700, height: 1.0),
                ),
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
                const Spacer(),
                const Icon(Icons.edit, size: 14, color: _orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
