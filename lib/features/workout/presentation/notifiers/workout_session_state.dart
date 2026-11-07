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

  /// 计时被用户手动暂停：秒数**冻结在当前值**，可随时继续
  /// （与"计时结束"区分：结束会走完成本组，暂停只是定住）
  final bool isTimerPaused;

  /// 休息倒计时被暂停（与 [isTimerPaused] 分开：两者时段不同）
  final bool isRestPaused;

  final bool isAutoMode;

  /// 倒计时朗读模式：'every' = 全亮（每秒都读）/ 'last3' = 321 版
  final String countdownVoiceMode;
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
    this.isTimerPaused = false,
    this.isRestPaused = false,
    this.isAutoMode = false,
    this.countdownVoiceMode = 'last3',
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
    bool? isTimerPaused,
    bool? isRestPaused,
    bool? isAutoMode,
    String? countdownVoiceMode,
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
      isTimerPaused: isTimerPaused ?? this.isTimerPaused,
      isRestPaused: isRestPaused ?? this.isRestPaused,
      isAutoMode: isAutoMode ?? this.isAutoMode,
      countdownVoiceMode: countdownVoiceMode ?? this.countdownVoiceMode,
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
