import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/countdown_controller.dart';
import 'package:fittrack/core/services/workout_coach.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

// ───────────────────── 统一 Exercise 槽位模型 ─────────────────────

/// 统一的训练动作槽位，自由训练和计划训练共用
class ExerciseSlot {
  final int exerciseId;
  final String exerciseName;
  final String category;
  final int targetSets;
  final int? targetReps;
  final double? targetWeightKg;
  final int? targetDurationSec;
  final int restSec;

  const ExerciseSlot({
    required this.exerciseId,
    required this.exerciseName,
    required this.category,
    required this.targetSets,
    this.targetReps,
    this.targetWeightKg,
    this.targetDurationSec,
    this.restSec = 90,
  });
}

// ───────────────────── 状态 ─────────────────────

class WorkoutSessionState {
  final List<ExerciseSlot> slots;
  final int currentSlotIndex;
  final int currentSetIndex;
  final List<NewSetData> completedSets;

  // 休息计时器
  final int restSeconds;
  final int restDurationSec;
  final bool isResting;

  // 训练计时器
  final int trainingSeconds;
  final int trainingDurationSec;
  final bool isTraining;

  final bool isAutoMode;
  final bool isComplete;
  final int paceIntervalSec;

  final String sessionType; // 'free' | 'plan'
  final int? planId;
  final DateTime? startTime;

  // 上一组输入值，供下一组预填
  final String? lastReps;
  final String? lastWeight;
  final String? lastDuration;

  const WorkoutSessionState({
    this.slots = const [],
    this.currentSlotIndex = 0,
    this.currentSetIndex = 0,
    this.completedSets = const [],
    this.restSeconds = 0,
    this.restDurationSec = 90,
    this.isResting = false,
    this.trainingSeconds = 0,
    this.trainingDurationSec = 60,
    this.isTraining = false,
    this.isAutoMode = false,
    this.isComplete = false,
    this.paceIntervalSec = 2,
    this.sessionType = 'free',
    this.planId,
    this.startTime,
    this.lastReps,
    this.lastWeight,
    this.lastDuration,
  });

  WorkoutSessionState copyWith({
    List<ExerciseSlot>? slots,
    int? currentSlotIndex,
    int? currentSetIndex,
    List<NewSetData>? completedSets,
    int? restSeconds,
    int? restDurationSec,
    bool? isResting,
    int? trainingSeconds,
    int? trainingDurationSec,
    bool? isTraining,
    bool? isAutoMode,
    bool? isComplete,
    int? paceIntervalSec,
    String? sessionType,
    int? planId,
    DateTime? startTime,
    String? lastReps,
    String? lastWeight,
    String? lastDuration,
    bool clearLastReps = false,
    bool clearLastWeight = false,
    bool clearLastDuration = false,
  }) {
    return WorkoutSessionState(
      slots: slots ?? this.slots,
      currentSlotIndex: currentSlotIndex ?? this.currentSlotIndex,
      currentSetIndex: currentSetIndex ?? this.currentSetIndex,
      completedSets: completedSets ?? this.completedSets,
      restSeconds: restSeconds ?? this.restSeconds,
      restDurationSec: restDurationSec ?? this.restDurationSec,
      isResting: isResting ?? this.isResting,
      trainingSeconds: trainingSeconds ?? this.trainingSeconds,
      trainingDurationSec: trainingDurationSec ?? this.trainingDurationSec,
      isTraining: isTraining ?? this.isTraining,
      isAutoMode: isAutoMode ?? this.isAutoMode,
      isComplete: isComplete ?? this.isComplete,
      paceIntervalSec: paceIntervalSec ?? this.paceIntervalSec,
      sessionType: sessionType ?? this.sessionType,
      planId: planId ?? this.planId,
      startTime: startTime ?? this.startTime,
      lastReps: clearLastReps ? null : (lastReps ?? this.lastReps),
      lastWeight: clearLastWeight ? null : (lastWeight ?? this.lastWeight),
      lastDuration: clearLastDuration ? null : (lastDuration ?? this.lastDuration),
    );
  }

  // ── 便捷 getter ──
  ExerciseSlot? get currentSlot =>
      currentSlotIndex < slots.length ? slots[currentSlotIndex] : null;
  bool get isLastSetOfCurrentSlot =>
      currentSlot != null && currentSetIndex >= currentSlot!.targetSets;
  bool get isLastSlot => currentSlotIndex >= slots.length - 1;
}

// ───────────────────── Notifier ─────────────────────

class WorkoutSessionNotifier extends StateNotifier<WorkoutSessionState> {
  final Ref _ref;
  final _restCtrl = CountdownController();
  final _trainingCtrl = CountdownController();
  final _coach = WorkoutCoach();
  bool _coachEnabled = true;

  WorkoutSessionNotifier(this._ref) : super(const WorkoutSessionState());

  // ── 初始化 ──

  /// 从自由训练初始化（page 已将 SelectedExercise 转为 ExerciseSlot）
  void initFree(List<ExerciseSlot> slots) {
    _applyVoiceSettings();
    _loadTimerDefaults();
    state = WorkoutSessionState(
      slots: slots,
      sessionType: 'free',
      startTime: DateTime.now(),
      restDurationSec: _defaultRestSec(),
      trainingDurationSec: _defaultTrainingSec(),
    );
  }

  /// 从计划训练初始化（异步加载计划数据和动作名称）
  Future<void> initPlan(int planId, int dayOfWeek) async {
    _applyVoiceSettings();
    _loadTimerDefaults();
    final planRepo = _ref.read(planRepoProvider);
    final exerciseRepo = _ref.read(exerciseRepoProvider);

    final plan = await planRepo.getById(planId);
    if (plan == null) return;

    final dayExercises = plan.days.where((d) => d.dayOfWeek == dayOfWeek).toList();
    final allEx = await exerciseRepo.getAll();
    final exMap = {for (final e in allEx) e.id: e};

    final slots = dayExercises.map((d) {
      final ex = exMap[d.exerciseId];
      return ExerciseSlot(
        exerciseId: d.exerciseId,
        exerciseName: ex?.name ?? '动作 #${d.exerciseId}',
        category: ex?.category ?? 'bodyweight',
        targetSets: d.targetSets,
        targetReps: d.targetReps,
        targetWeightKg: d.targetWeightKg,
        targetDurationSec: d.targetDurationSec,
        restSec: d.restSec,
      );
    }).toList();

    state = WorkoutSessionState(
      slots: slots,
      sessionType: 'plan',
      planId: planId,
      startTime: DateTime.now(),
      restDurationSec: _defaultRestSec(),
      trainingDurationSec: _defaultTrainingSec(),
    );
  }

  void _applyVoiceSettings() {
    final s = _ref.read(userSettingsProvider).valueOrNull;
    _coach.applySettings(
      rate: s?.speechRate ?? 0.45,
      pitch: s?.speechPitch ?? 1.0,
      voiceName: s?.ttsVoice,
    );
    _coachEnabled = (s?.speechRate ?? 0.45) > 0;
    _coach.enabled = _coachEnabled;
  }

  void _loadTimerDefaults() {
    // Stored for use during init
  }

  int _defaultTrainingSec() {
    final s = _ref.read(userSettingsProvider).valueOrNull;
    return (s?.defaultTrainingSec != null && s!.defaultTrainingSec! > 0)
        ? s.defaultTrainingSec!
        : 60;
  }

  int _defaultRestSec() {
    final s = _ref.read(userSettingsProvider).valueOrNull;
    return (s?.defaultRestSec != null && s!.defaultRestSec! > 0)
        ? s.defaultRestSec!
        : 90;
  }

  // ── 动作执行 ──

  /// 完成当前组
  void completeCurrentSet({
    required String? reps,
    required String? weight,
    required String? duration,
    bool isWarmup = false,
  }) {
    final slot = state.currentSlot;
    if (slot == null) return;

    // 保存输入到 last
    final lastReps = (reps != null && reps.isNotEmpty) ? reps : state.lastReps;
    final lastWeight = (weight != null && weight.isNotEmpty) ? weight : state.lastWeight;
    final lastDuration = (duration != null && duration.isNotEmpty) ? duration : state.lastDuration;

    // 添加到已完成组
    final newSet = NewSetData(
      exerciseId: slot.exerciseId,
      setNumber: state.currentSetIndex + 1,
      reps: int.tryParse(reps ?? '') ?? int.tryParse(state.lastReps ?? ''),
      weightKg: double.tryParse(weight ?? '') ?? double.tryParse(state.lastWeight ?? ''),
      durationSec: int.tryParse(duration ?? '') ?? int.tryParse(state.lastDuration ?? ''),
      isWarmup: isWarmup,
    );

    final newCompleted = [...state.completedSets, newSet];

    _coach.stopPace();
    _coach.announceSetEnd(state.currentSetIndex + 1);

    // 保存为动作默认值
    _saveExerciseDefaults(reps: reps, weight: weight, duration: duration);

    final nextSetIndex = state.currentSetIndex + 1;
    if (nextSetIndex < slot.targetSets) {
      // 还有下一组
      state = state.copyWith(
        currentSetIndex: nextSetIndex,
        completedSets: newCompleted,
        lastReps: lastReps,
        lastWeight: lastWeight,
        lastDuration: lastDuration,
      );
      if (!state.isAutoMode) {
        _startRest(slot.restSec);
      }
    } else {
      // 当前动作所有组完成
      state = state.copyWith(
        currentSetIndex: nextSetIndex,
        completedSets: newCompleted,
        lastReps: lastReps,
        lastWeight: lastWeight,
        lastDuration: lastDuration,
        isAutoMode: false,
      );
    }
  }

  /// 跳过当前组（无输入直接标记完成）
  void skipCurrentSet() {
    completeCurrentSet(reps: '', weight: '', duration: '');
  }

  /// 下一个动作
  void nextExercise() {
    _stopAutoMode();
    final nextIndex = state.currentSlotIndex + 1;
    if (nextIndex >= state.slots.length) {
      state = state.copyWith(isComplete: true);
    } else {
      state = state.copyWith(
        currentSlotIndex: nextIndex,
        currentSetIndex: 0,
        clearLastReps: true,
        clearLastWeight: true,
        clearLastDuration: true,
      );
    }
  }

  /// 保存当前输入作为动作默认值
  Future<void> _saveExerciseDefaults({
    String? reps,
    String? weight,
    String? duration,
  }) async {
    final slot = state.currentSlot;
    if (slot == null) return;
    final r = int.tryParse(reps ?? '') ?? int.tryParse(state.lastReps ?? '');
    final w = double.tryParse(weight ?? '') ?? double.tryParse(state.lastWeight ?? '');
    final d = int.tryParse(duration ?? '') ?? int.tryParse(state.lastDuration ?? '');
    await _ref.read(exerciseRepoProvider).saveDefaults(
      slot.exerciseId,
      defaultReps: r,
      defaultWeightKg: w,
      defaultDurationSec: d,
    );
  }

  /// 保存计时器默认值
  Future<void> _saveTimerDefaults() async {
    await _ref.read(userSettingsRepoProvider).save(
      defaultTrainingSec: state.trainingDurationSec,
      defaultRestSec: state.restDurationSec,
    );
  }

  // ── 休息计时器 ──

  void _startRest(int durationSec) {
    if (durationSec <= 0) return;
    state = state.copyWith(
      restSeconds: durationSec,
      restDurationSec: durationSec,
      isResting: true,
    );
    if (_coachEnabled) _coach.speak('休息$durationSec秒');
    _restCtrl.start(durationSec,
      onTick: _onRestTick,
      onComplete: _onRestComplete,
    );
  }

  void startRest() {
    _startRest(state.restDurationSec);
  }

  void stopRest() {
    _restCtrl.cancel();
    state = state.copyWith(isResting: false, restSeconds: 0);
  }

  void _onRestTick() {
    state = state.copyWith(restSeconds: state.restSeconds - 1);
    _coach.speak('${state.restSeconds}');
  }

  void _onRestComplete() {
    state = state.copyWith(isResting: false, restSeconds: 0);
    if (state.isAutoMode) {
      _startTraining();
    }
  }

  // ── 训练计时器 ──

  void _startTraining() {
    final slot = state.currentSlot;
    if (slot == null) return;
    state = state.copyWith(
      trainingSeconds: state.trainingDurationSec,
      isTraining: true,
      isAutoMode: true,
    );

    if (_coachEnabled) {
      _coach.announceSetStart(slot.exerciseName, state.currentSetIndex + 1);
    }

    final isTimed = slot.category == 'cardio' || slot.category == 'stretch';
    if (!isTimed) {
      _coach.startPace(state.paceIntervalSec * 1000, () {});
    }

    _trainingCtrl.start(state.trainingDurationSec,
      onTick: _onTrainingTick,
      onComplete: _onTrainingComplete,
    );
  }

  void startTraining() {
    _startTraining();
  }

  void _onTrainingTick() {
    state = state.copyWith(trainingSeconds: state.trainingSeconds - 1);
    _coach.speak('${state.trainingSeconds}');
  }

  void _onTrainingComplete() {
    _stopAutoModeStateOnly();
    // 自动完成当前组
    final slot = state.currentSlot;
    if (slot == null) return;

    final newSet = NewSetData(
      exerciseId: slot.exerciseId,
      setNumber: state.currentSetIndex + 1,
      reps: int.tryParse(state.lastReps ?? ''),
      weightKg: double.tryParse(state.lastWeight ?? ''),
      durationSec: int.tryParse(state.lastDuration ?? ''),
    );

    final newCompleted = [...state.completedSets, newSet];
    _coach.stopPace();
    _coach.announceSetEnd(state.currentSetIndex + 1);

    final nextSetIndex = state.currentSetIndex + 1;
    if (nextSetIndex < slot.targetSets) {
      state = state.copyWith(
        currentSetIndex: nextSetIndex,
        completedSets: newCompleted,
        isAutoMode: false,
        isTraining: false,
        trainingSeconds: 0,
      );
      _startRest(slot.restSec);
    } else {
      state = state.copyWith(
        currentSetIndex: nextSetIndex,
        completedSets: newCompleted,
        isAutoMode: false,
        isTraining: false,
        trainingSeconds: 0,
      );
    }
  }

  // ── 自动模式控制 ──

  void _stopAutoMode() {
    _trainingCtrl.cancel();
    _restCtrl.cancel();
    _coach.stopPace();
    state = state.copyWith(
      isAutoMode: false,
      isTraining: false,
      isResting: false,
      trainingSeconds: 0,
      restSeconds: 0,
    );
  }

  /// 只停止自动模式状态（不 cancel timer，timer 已自然结束）
  void _stopAutoModeStateOnly() {
    _trainingCtrl.cancel();
    _restCtrl.cancel();
    _coach.stopPace();
  }

  void stopAutoMode() => _stopAutoMode();

  // ── 设置 ──

  void setRestDurationSec(int sec) {
    if (sec > 0) {
      state = state.copyWith(restDurationSec: sec);
      _saveTimerDefaults();
    }
  }

  void setTrainingDurationSec(int sec) {
    if (sec > 0) {
      state = state.copyWith(trainingDurationSec: sec);
      _saveTimerDefaults();
    }
  }

  void setPaceIntervalSec(int sec) {
    state = state.copyWith(paceIntervalSec: sec);
  }

  void setVoiceEnabled(bool enabled) {
    _coachEnabled = enabled;
    _coach.enabled = enabled;
    if (!enabled) _coach.stopPace();
  }

  bool get voiceEnabled => _coachEnabled;

  // ── 保存训练 ──

  Future<void> saveWorkout() async {
    _coach.announceWorkoutDone().catchError((_) {});
    final repo = _ref.read(workoutRepoProvider);
    final durationSec = state.startTime != null
        ? DateTime.now().difference(state.startTime!).inSeconds
        : null;
    await repo.createWorkout(
      date: DateTime.now(),
      type: state.sessionType,
      planId: state.planId,
      durationSec: durationSec,
      sets: state.completedSets,
    );
    // 自动更新训练频率目标
    final goals = await _ref.read(goalRepoProvider).getAll();
    for (final g in goals.where((g) => g.type == 'frequency' && !g.isCompleted)) {
      await _ref.read(goalRepoProvider).updateProgress(g.id, g.currentValue + 1);
    }
  }

  // ── 上一组回退 ──

  void prevSet() {
    if (state.currentSetIndex > 0 && !state.isAutoMode) {
      state = state.copyWith(currentSetIndex: state.currentSetIndex - 1);
    }
  }

  // ── 清理 ──

  @override
  void dispose() {
    _restCtrl.dispose();
    _trainingCtrl.dispose();
    _coach.stopPace();
    super.dispose();
  }
}

// ── Provider ──

final workoutSessionProvider =
    StateNotifierProvider<WorkoutSessionNotifier, WorkoutSessionState>(
  (ref) => WorkoutSessionNotifier(ref),
);
