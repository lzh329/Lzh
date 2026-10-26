import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/countdown_controller.dart';
import 'package:fittrack/core/services/workout_coach.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';
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

  /// 循环训练：当前轮次（1 基）与总轮数
  final int currentRound;
  final int totalRounds;

  /// 循环训练休息节奏：动作间短休息 / 轮间长休息（秒）
  final int restShortSec;
  final int restLongSec;

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
    this.currentRound = 1,
    this.totalRounds = 4,
    this.restShortSec = 15,
    this.restLongSec = 60,
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
    int? currentRound,
    int? totalRounds,
    int? restShortSec,
    int? restLongSec,
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
      currentRound: currentRound ?? this.currentRound,
      totalRounds: totalRounds ?? this.totalRounds,
      restShortSec: restShortSec ?? this.restShortSec,
      restLongSec: restLongSec ?? this.restLongSec,
      sessionType: sessionType ?? this.sessionType,
      planId: planId ?? this.planId,
      startTime: startTime ?? this.startTime,
      lastReps: clearLastReps ? null : (lastReps ?? this.lastReps),
      lastWeight: clearLastWeight ? null : (lastWeight ?? this.lastWeight),
      lastDuration:
          clearLastDuration ? null : (lastDuration ?? this.lastDuration),
    );
  }

  // ── 便捷 getter ──
  ExerciseSlot? get currentSlot =>
      currentSlotIndex < slots.length ? slots[currentSlotIndex] : null;
  bool get isLastSetOfCurrentSlot => currentRound >= totalRounds && isLastSlot;
  bool get isLastSlot => currentSlotIndex >= slots.length - 1;

  /// 循环模式：本轮内动作进度（1 基 / 总数）
  int get roundActionIndex => currentSlotIndex + 1;

  /// 轮数：取各动作目标组数的最大值
  int roundsOf(List<ExerciseSlot> slots) {
    if (slots.isEmpty) return 1;
    return slots.map((s) => s.targetSets).fold(1, (a, b) => a > b ? a : b);
  }
}

// ───────────────────── Notifier ─────────────────────

class WorkoutSessionNotifier extends StateNotifier<WorkoutSessionState> {
  final Ref _ref;
  final _restCtrl = CountdownController();
  final _trainingCtrl = CountdownController();
  final _coach = WorkoutCoach();
  bool _coachEnabled = true;

  /// 本次计时倒计时的总时长（用于跳过开场播报的静默期）
  int _trainingTotal = 0;

  // ── 前后台切换（避免回到桌面后计时与语音仍在继续）──
  bool _paused = false;
  int _pausedRestSec = 0;
  int _pausedRestTotalSec = 0;
  int _pausedTrainingSec = 0;
  int _pausedTrainingTotalSec = 0;

  WorkoutSessionNotifier(this._ref) : super(const WorkoutSessionState());

  // ── 初始化 ──

  /// 从自由训练初始化（page 已将 SelectedExercise 转为 ExerciseSlot）
  void initFree(List<ExerciseSlot> slots) {
    _paused = false;
    _pausedRestSec = 0;
    _pausedTrainingSec = 0;
    _applyVoiceSettings();
    _loadTimerDefaults();
    state = WorkoutSessionState(
      slots: slots,
      sessionType: 'free',
      startTime: DateTime.now(),
      restDurationSec: _defaultRestSec(),
      trainingDurationSec: _defaultTrainingSec(),
      restShortSec: _defaultRestShortSec(),
      restLongSec: _defaultRestLongSec(),
      totalRounds:
          slots.map((s) => s.targetSets).fold(1, (a, b) => a > b ? a : b),
    );
  }

  /// 从计划训练初始化（异步加载计划数据和动作名称）
  Future<void> initPlan(int planId, int dayOfWeek) async {
    _paused = false;
    _pausedRestSec = 0;
    _pausedTrainingSec = 0;
    _applyVoiceSettings();
    _loadTimerDefaults();
    final planRepo = _ref.read(planRepoProvider);
    final exerciseRepo = _ref.read(exerciseRepoProvider);

    final plan = await planRepo.getById(planId);
    if (plan == null) return;

    final dayExercises =
        plan.days.where((d) => d.dayOfWeek == dayOfWeek).toList();
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
      restShortSec: _defaultRestShortSec(),
      restLongSec: _defaultRestLongSec(),
      totalRounds:
          slots.map((s) => s.targetSets).fold(1, (a, b) => a > b ? a : b),
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
    // 设置已加载完（常见路径）：init 里已经同步取过值，无需再补
    if (_ref.read(userSettingsProvider).valueOrNull != null) return;

    // 冷启动直接开练时 provider 可能还没 resolve → 异步补一次
    _ref.read(userSettingsRepoProvider).get().then((s) {
      if (!mounted || s == null) return;
      state = state.copyWith(
        restShortSec: (s.restShortSec != null && s.restShortSec! > 0)
            ? s.restShortSec!
            : state.restShortSec,
        restLongSec: (s.restLongSec != null && s.restLongSec! > 0)
            ? s.restLongSec!
            : state.restLongSec,
        trainingDurationSec:
            (s.defaultTrainingSec != null && s.defaultTrainingSec! > 0)
                ? s.defaultTrainingSec!
                : state.trainingDurationSec,
      );
    }).catchError((Object e) {
      debugPrint('加载计时器默认值失败: $e');
    });
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

  /// 循环模式：动作间休息（上次设置的值，默认 15 秒）
  int _defaultRestShortSec() {
    final s = _ref.read(userSettingsProvider).valueOrNull;
    return (s?.restShortSec != null && s!.restShortSec! > 0)
        ? s.restShortSec!
        : 15;
  }

  /// 循环模式：轮间休息（上次设置的值，默认 60 秒）
  int _defaultRestLongSec() {
    final s = _ref.read(userSettingsProvider).valueOrNull;
    return (s?.restLongSec != null && s!.restLongSec! > 0)
        ? s.restLongSec!
        : 60;
  }

  // ── 动作执行（循环模式：每个动作每轮做 1 组，轮内短休息、轮间长休息）──

  /// 完成当前动作（本轮的这 1 组）
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
    final lastWeight =
        (weight != null && weight.isNotEmpty) ? weight : state.lastWeight;
    final lastDuration = (duration != null && duration.isNotEmpty)
        ? duration
        : state.lastDuration;

    // 计时类动作只记录时长，力量类只记录次数（避免平板支撑存成"次数"）
    final isTimed = slot.category == 'cardio' ||
        slot.category == 'stretch' ||
        slot.targetDurationSec != null;
    final newSet = NewSetData(
      exerciseId: slot.exerciseId,
      setNumber: state.currentRound,
      reps: isTimed
          ? null
          : (int.tryParse(reps ?? '') ??
              int.tryParse(state.lastReps ?? '') ??
              slot.targetReps),
      weightKg: isTimed
          ? null
          : (double.tryParse(weight ?? '') ??
              double.tryParse(state.lastWeight ?? '') ??
              slot.targetWeightKg),
      durationSec: isTimed
          ? (int.tryParse(duration ?? '') ??
              int.tryParse(state.lastDuration ?? '') ??
              slot.targetDurationSec ??
              state.trainingDurationSec)
          : null,
      isWarmup: isWarmup,
    );

    final newCompleted = [...state.completedSets, newSet];

    _coach.stopPace();
    _coach.announceSetEnd(state.currentRound);
    _saveExerciseDefaults(reps: reps, weight: weight, duration: duration);

    final isLastSlot = state.currentSlotIndex >= state.slots.length - 1;
    final isLastRound = state.currentRound >= state.totalRounds;

    // ① 最后一轮 · 最后一个动作 → 完成训练
    if (isLastSlot && isLastRound) {
      state = state.copyWith(
        completedSets: newCompleted,
        lastReps: lastReps,
        lastWeight: lastWeight,
        lastDuration: lastDuration,
        isResting: false,
        restSeconds: 0,
        isComplete: true,
      );
      if (_coachEnabled) _coach.announceWorkoutDone();
      NotificationService().hideWorkoutOngoing();
      return;
    }

    // ② 轮末 → 长休息，进入下一轮第一个动作
    if (isLastSlot) {
      state = state.copyWith(
        currentRound: state.currentRound + 1,
        currentSlotIndex: 0,
        completedSets: newCompleted,
        lastReps: lastReps,
        lastWeight: lastWeight,
        lastDuration: lastDuration,
      );
      _startRest(state.restLongSec, isRoundBreak: true);
      // 休息时长为 0（不休息）时直接开始下一轮的计时类动作
      if (!state.isResting) _autoStartTimedIfNeeded();
      return;
    }

    // ③ 轮内 → 短休息，进入下一个动作
    state = state.copyWith(
      currentSlotIndex: state.currentSlotIndex + 1,
      completedSets: newCompleted,
      lastReps: lastReps,
      lastWeight: lastWeight,
      lastDuration: lastDuration,
    );
    _startRest(state.restShortSec);
    // 休息时长为 0（不休息）时直接开始下一个计时类动作
    if (!state.isResting) _autoStartTimedIfNeeded();
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
      // 切过去的动作是计时类 → 直接开始倒计时
      _autoStartTimedIfNeeded();
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
    final w = double.tryParse(weight ?? '') ??
        double.tryParse(state.lastWeight ?? '');
    final d =
        int.tryParse(duration ?? '') ?? int.tryParse(state.lastDuration ?? '');
    await _ref.read(exerciseRepoProvider).saveDefaults(
          slot.exerciseId,
          defaultReps: r,
          defaultWeightKg: w,
          defaultDurationSec: d,
        );
  }

  /// 保存计时器默认值
  ///
  /// 属于「顺手持久化」，与训练流程无关；UserSettings 尚未初始化或写库失败时
  /// 只记录日志，绝不能把异常抛给调用方（否则会出现未捕获异常红屏）。
  Future<void> _saveTimerDefaults() async {
    try {
      await _ref.read(userSettingsRepoProvider).save(
            defaultTrainingSec: state.trainingDurationSec,
            defaultRestSec: state.restDurationSec,
            restShortSec: state.restShortSec,
            restLongSec: state.restLongSec,
          );
    } catch (e) {
      debugPrint('保存计时器默认值失败: $e');
    }
  }

  // ── 休息计时器 ──

  /// 是否计时类动作（有氧 / 拉伸 / 带目标时长的静力动作如平板支撑）
  bool _isTimedSlot(ExerciseSlot? slot) {
    return slot != null &&
        (slot.category == 'cardio' ||
            slot.category == 'stretch' ||
            slot.targetDurationSec != null);
  }

  /// 当前动作是计时类、且当前既不在休息也不在计时 → 自动开始倒计时
  ///
  /// 用于所有「推进到新动作」的路径：完成一组、跳过休息、下一个动作、无休息直进。
  /// 这样不管用户中途手动停止过计时，下一组计时类动作都会自己跑起来。
  void _autoStartTimedIfNeeded() {
    if (state.isResting || _restCtrl.isActive) return;
    // 用控制器真实运行状态判断，避免状态里残留的 isAutoMode 挡住自动开始
    if (_trainingCtrl.isActive) return;
    if (_isTimedSlot(state.currentSlot)) {
      _startTraining();
    }
  }

  void _startRest(int durationSec, {bool isRoundBreak = false}) {
    if (durationSec <= 0) return;
    state = state.copyWith(
      restSeconds: durationSec,
      restDurationSec: durationSec,
      isResting: true,
    );
    if (_coachEnabled) {
      _coach.speakImmediate(
        isRoundBreak
            ? '第${state.currentRound}轮，休息$durationSec秒'
            : '休息$durationSec秒',
      );
    }
    _restCtrl.start(
      durationSec,
      onTick: _onRestTick,
      onComplete: _onRestComplete,
    );
    _syncOngoing();
  }

  void startRest() {
    _startRest(state.restShortSec);
  }

  void stopRest() {
    _restCtrl.cancel();
    // 清掉上一段计时残留的自动标记，否则自动开始会被 isAutoMode 挡住
    state = state.copyWith(
      isResting: false,
      restSeconds: 0,
      isTraining: false,
      trainingSeconds: 0,
      isAutoMode: false,
    );
    // 跳过休息时立刻清空未播完的语音，避免「已经结束了还在念数字」
    _coach.stop();
    // 跳过休息后若当前动作是计时类 → 直接开始倒计时（不用再手动点）
    _autoStartTimedIfNeeded();
    _syncOngoing();
  }

  /// 休息每秒回调
  ///
  /// 原先每秒都 speak 一次，TTS 队列严重堆积（播报落后数秒、休息结束后仍在念数字）。
  /// 现在只在关键节点用 [WorkoutCoach.speakImmediate] 播报，其余秒静默。
  void _onRestTick() {
    final next = state.restSeconds - 1;
    state = state.copyWith(restSeconds: next);
    // 全程播报（speakImmediate 打断式，保证不排队积压）
    if (_coachEnabled && next > 0) {
      _coach.speakImmediate('$next');
    }
    if (next % 5 == 0) _syncOngoing();
  }

  void _onRestComplete() {
    state = state.copyWith(isResting: false, restSeconds: 0);
    final slot = state.currentSlot;
    if (slot == null) return;

    // 下一动作是计时类 → 休息结束自动开始倒计时
    if (_isTimedSlot(slot)) {
      _startTraining();
      return;
    }

    if (_coachEnabled) {
      _coach.speakImmediate('${slot.exerciseName}，准备');
    }
  }

  // ── 训练计时器 ──

  void _startTraining() {
    final slot = state.currentSlot;
    if (slot == null) return;
    // 计时类动作用动作自身的目标时长（平板支撑 30s / 拉伸 60s）
    final duration = slot.targetDurationSec ?? state.trainingDurationSec;
    _trainingTotal = duration;
    state = state.copyWith(
      trainingSeconds: duration,
      isTraining: true,
      isAutoMode: true,
    );

    final isTimed = slot.category == 'cardio' ||
        slot.category == 'stretch' ||
        slot.targetDurationSec != null;

    if (_coachEnabled) {
      if (isTimed) {
        // 计时动作不播 3/2/1（会和倒计时播报重叠），只播动作名 + 开始
        _coach.speakImmediate('${slot.exerciseName}，开始');
      } else {
        _coach.announceSetStart(slot.exerciseName, state.currentRound);
      }
    }

    if (!isTimed) {
      _coach.startPace(state.paceIntervalSec * 1000, () {});
    }

    _trainingCtrl.start(
      duration,
      onTick: _onTrainingTick,
      onComplete: _onTrainingComplete,
    );
    _syncOngoing();
  }

  void startTraining() {
    _startTraining();
  }

  /// 训练每秒回调：仅在最后 5 秒做关键播报，避免 TTS 队列堆积
  void _onTrainingTick() {
    final next = state.trainingSeconds - 1;
    state = state.copyWith(trainingSeconds: next);
    // 开场"动作名，开始"占约 2 秒 → 前 3 秒静默，避免与 59/58 播报重叠
    if (_coachEnabled && next > 0 && next <= _trainingTotal - 3) {
      _coach.speakImmediate('$next');
    }
    if (next % 5 == 0) _syncOngoing();
  }

  void _onTrainingComplete() {
    _stopAutoModeStateOnly();
    if (state.currentSlot == null) return;

    // 计时结束 = 完成本轮该动作的 1 组 → 复用循环推进
    // （短/长休息 → 下一动作；下一动作是计时类 → 休息结束自动倒计时）
    completeCurrentSet(
      reps: null,
      weight: null,
      duration: _trainingTotal > 0 ? '$_trainingTotal' : null,
    );
  }

  // ── 训练常驻通知（锁屏/通知栏可见，切出去也能看到进度）──

  String _fmtClock(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// 按当前状态刷新常驻通知（秒级 tick 每 5 秒调一次即可）
  void _syncOngoing() {
    final slot = state.currentSlot;
    if (slot == null || state.isComplete) {
      NotificationService().hideWorkoutOngoing();
      return;
    }
    final title = '训练中 · 第${state.currentRound}/${state.totalRounds}轮 · '
        '动作${state.currentSlotIndex + 1}/${state.slots.length}';

    String status;
    if (state.isResting) {
      final nextIdx = state.currentSlotIndex + 1;
      final nextName = nextIdx < state.slots.length
          ? state.slots[nextIdx].exerciseName
          : '下一轮';
      status = '休息 ${_fmtClock(state.restSeconds)} · 下一个：$nextName';
    } else if (state.isTraining) {
      status = '${slot.exerciseName} · 倒计时 ${_fmtClock(state.trainingSeconds)}';
    } else {
      status = '${slot.exerciseName} · 继续完成本轮';
    }

    NotificationService().showWorkoutOngoing(title: title, text: status);
  }

  // ── 前后台切换 / 离开页面 ──

  /// 应用切到后台：暂停休息/训练倒计时并立刻停掉语音
  ///
  /// 不这么做的话，Dart 定时器在后台会继续 tick，TTS 会在桌面上一直念数字。
  void pauseForBackground() {
    if (_paused) return;
    _paused = true;

    _pausedRestSec = state.isResting ? state.restSeconds : 0;
    _pausedRestTotalSec = state.isResting ? state.restDurationSec : 0;
    _pausedTrainingSec = state.isTraining ? state.trainingSeconds : 0;
    _pausedTrainingTotalSec = _trainingTotal;

    _restCtrl.cancel();
    _trainingCtrl.cancel();
    _coach.stopPace();
    _coach.stop();

    if (_pausedRestSec > 0 || _pausedTrainingSec > 0) {
      // 暂停期间 UI 不显示倒计时，回来时再恢复
      state = state.copyWith(
        isResting: false,
        isTraining: false,
        isAutoMode: false,
        restSeconds: 0,
        trainingSeconds: 0,
      );
      NotificationService().showWorkoutOngoing(
        title: '训练已暂停',
        text: '回到 App 从暂停处继续',
      );
    }
  }

  /// 回到前台：从暂停处继续（休息 / 计时各自恢复剩余秒数）
  void resumeFromBackground() {
    if (!_paused) return;
    _paused = false;

    if (_pausedRestSec > 0) {
      final remain = _pausedRestSec;
      final total =
          _pausedRestTotalSec > 0 ? _pausedRestTotalSec : _pausedRestSec;
      _pausedRestSec = 0;
      state = state.copyWith(
        restSeconds: remain,
        restDurationSec: total,
        isResting: true,
      );
      if (_coachEnabled) _coach.speakImmediate('继续休息$remain秒');
      _restCtrl.start(remain, onTick: _onRestTick, onComplete: _onRestComplete);
      return;
    }

    if (_pausedTrainingSec > 0) {
      final remain = _pausedTrainingSec;
      _pausedTrainingSec = 0;
      _trainingTotal = _pausedTrainingTotalSec > 0
          ? _pausedTrainingTotalSec
          : _pausedTrainingSec;
      state = state.copyWith(
        trainingSeconds: remain,
        isTraining: true,
        isAutoMode: true,
      );
      if (_coachEnabled) _coach.speakImmediate('继续，还剩$remain秒');
      _trainingCtrl.start(remain,
          onTick: _onTrainingTick, onComplete: _onTrainingComplete);
    }
  }

  /// 离开训练页：彻底停掉计时与语音（不保留恢复点）
  void stopAllTimersAndVoice() {
    _paused = false;
    _pausedRestSec = 0;
    _pausedTrainingSec = 0;
    _restCtrl.cancel();
    _trainingCtrl.cancel();
    _coach.stopPace();
    _coach.stop();
    NotificationService().hideWorkoutOngoing();
  }

  // ── 自动模式控制 ──

  void _stopAutoMode() {
    _trainingCtrl.cancel();
    _restCtrl.cancel();
    _coach.stopPace();
    // 停止计时后同步清空语音队列
    _coach.stop();
    state = state.copyWith(
      isAutoMode: false,
      isTraining: false,
      isResting: false,
      trainingSeconds: 0,
      restSeconds: 0,
    );
  }

  /// 只停止自动模式状态（不 cancel timer，timer 已自然结束）
  ///
  /// 注意：此处不清空语音（不调用 `_coach.stop()`），
  /// 因为紧接着会播报「第 X 组已结束」，避免平台通道竞态把播报吞掉。
  void _stopAutoModeStateOnly() {
    _trainingCtrl.cancel();
    _restCtrl.cancel();
    _coach.stopPace();
    // 计时已结束：清掉训练态（否则界面会停在最后一次的秒数/自动标记上）
    state = state.copyWith(
      isTraining: false,
      trainingSeconds: 0,
      isAutoMode: false,
    );
  }

  void stopAutoMode() => _stopAutoMode();

  // ── 设置 ──

  /// 设置休息时长（秒）
  ///
  /// - 正数才生效；先更新状态再异步落盘，落盘异常已被 [_saveTimerDefaults] 吞掉
  /// - 若当前正处于休息中，立即按新时长重启倒计时（符合用户「改了马上生效」的预期）
  /// 循环模式：动作间休息（秒）
  void setRestShortSec(int sec) {
    if (sec <= 0) return;
    state = state.copyWith(restShortSec: sec);
    // 落盘：下次开始训练仍是这个值
    _saveTimerDefaults();
  }

  /// 循环模式：轮间休息（秒）
  void setRestLongSec(int sec) {
    if (sec <= 0) return;
    state = state.copyWith(restLongSec: sec);
    _saveTimerDefaults();
  }

  void setRestDurationSec(int sec) {
    if (sec <= 0) return;
    final wasResting = state.isResting;
    state = state.copyWith(restDurationSec: sec);
    if (wasResting) {
      _startRest(sec);
    }
    _saveTimerDefaults();
  }

  /// 设置训练时长（秒）
  ///
  /// 训练计时进行中不打断当前倒计时，只更新默认值，下一组生效。
  void setTrainingDurationSec(int sec) {
    if (sec <= 0) return;
    state = state.copyWith(trainingDurationSec: sec);
    _saveTimerDefaults();
  }

  /// 调整「当前动作」的目标时长（计时类动作，从训练设置里修改）
  ///
  /// 与 [setTrainingDurationSec]（计时类动作的默认时长）区分：
  /// 单个动作若已带目标时长，会覆盖默认值，所以需要能按动作改。
  void setCurrentSlotDurationSec(int sec) {
    if (sec <= 0) return;
    final idx = state.currentSlotIndex;
    if (idx < 0 || idx >= state.slots.length) return;

    final slot = state.slots[idx];
    final slots = [...state.slots];
    slots[idx] = ExerciseSlot(
      exerciseId: slot.exerciseId,
      exerciseName: slot.exerciseName,
      category: slot.category,
      targetSets: slot.targetSets,
      targetReps: slot.targetReps,
      targetWeightKg: slot.targetWeightKg,
      targetDurationSec: sec,
      restSec: slot.restSec,
    );
    state = state.copyWith(slots: slots);

    // 正在倒数该动作 → 立即按新时长重启（避免"改了没生效"）
    if (state.isTraining) {
      _startTraining();
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
    for (final g
        in goals.where((g) => g.type == 'frequency' && !g.isCompleted)) {
      await _ref
          .read(goalRepoProvider)
          .updateProgress(g.id, g.currentValue + 1);
    }

    // 让所有依赖训练数据的页面立即刷新（训练历史 / 首页 / 趋势 / 目标）
    _ref.invalidate(workoutHistoryProvider);
    _ref.invalidate(dashboardDataProvider);
    _ref.invalidate(trendsDataProvider);
    _ref.invalidate(goalListProvider);
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
