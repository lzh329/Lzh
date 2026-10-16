import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

class WorkoutDetailPage extends ConsumerWidget {
  final int workoutId;
  const WorkoutDetailPage({super.key, required this.workoutId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(dashboardRefreshCount); // 编辑返回后触发刷新
    final workoutRepo = ref.watch(workoutRepoProvider);
    final exerciseRepo = ref.watch(exerciseRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareWorkout(context, ref, workoutRepo, exerciseRepo, workoutId),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _editWorkout(context, ref, workoutRepo),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref, workoutRepo),
          ),
        ],
      ),
      body: FutureBuilder<_DetailData?>(
        future: _loadDetail(workoutRepo, workoutId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null || data.workout == null) {
            return const Center(child: Text('训练记录不存在'));
          }
          final workout = data.workout!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('yyyy年MM月dd日 EEEE').format(workout.date),
                        style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('${workout.totalSets} 组 · ${workout.completedSets} 组完成',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                      if (workout.note != null && workout.note!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('备注：${workout.note}',
                          style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ..._groupSetsByExercise(workout.sets).entries.map((entry) {
                return FutureBuilder<ExerciseEntity?>(
                  future: exerciseRepo.getById(entry.key),
                  builder: (context, snap) {
                    final exercise = snap.data;
                    final exerciseName = exercise?.name ?? '动作 #${entry.key}';
                    final category = exercise?.category ?? 'bodyweight';

                    // PR tracking
                    final bestWeight = data.prs['${entry.key}_weight'] ?? 0.0;
                    final bestReps = data.prs['${entry.key}_reps'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppTheme.categoryColors[category] ?? Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(exerciseName, style: theme.textTheme.titleSmall),
                                if (exercise?.muscleGroup != null)
                                  Text(' · ${exercise!.muscleGroup}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...entry.value.map((set) {
                              final isWeightPR = set.weightKg != null && set.weightKg! > 0 && set.weightKg! >= bestWeight && bestWeight > 0;
                              final isRepsPR = set.reps != null && set.reps! > 0 && set.reps! >= bestReps && bestReps > 0;
                              final isPR = isWeightPR || isRepsPR;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: set.isWarmup
                                          ? Colors.orange.withAlpha(40)
                                          : theme.colorScheme.primaryContainer,
                                      ),
                                      child: Center(
                                        child: Text('${set.setNumber}',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                                            color: set.isWarmup ? Colors.orange : theme.colorScheme.onPrimaryContainer)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    if (set.reps != null) ...[
                                      Text('${set.reps} 次',
                                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                    ],
                                    if (set.weightKg != null && set.weightKg! > 0) ...[
                                      Text('${set.weightKg!.toStringAsFixed(1)} kg',
                                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                    ],
                                    if (set.durationSec != null) ...[
                                      Text(_fmt(set.durationSec!),
                                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                                    ],
                                    if (set.isWarmup)
                                      Chip(label: const Text('热身', style: TextStyle(fontSize: 10)),
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        backgroundColor: Colors.orange.withAlpha(30)),
                                    if (isPR)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Chip(
                                          label: Text('PR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          backgroundColor: Colors.amber,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Future<_DetailData?> _loadDetail(WorkoutRepository repo, int id) async {
    final workout = await repo.getById(id);
    if (workout == null) return null;

    // Compute PRs from all historical workouts
    final allWorkouts = await repo.getAll();
    final prs = <String, double>{};

    for (final w in allWorkouts) {
      if (w.id == id) continue; // exclude current workout
      for (final set in w.sets) {
        final wKey = '${set.exerciseId}_weight';
        final rKey = '${set.exerciseId}_reps';
        if (set.weightKg != null && (prs[wKey] ?? 0) < set.weightKg!) {
          prs[wKey] = set.weightKg!;
        }
        if (set.reps != null && (prs[rKey] ?? 0) < set.reps!.toDouble()) {
          prs[rKey] = set.reps!.toDouble();
        }
      }
    }

    return _DetailData(workout: workout, prs: prs);
  }

  Map<int, List<WorkoutSetEntity>> _groupSetsByExercise(List<WorkoutSetEntity> sets) {
    final map = <int, List<WorkoutSetEntity>>{};
    for (final set in sets) {
      map.putIfAbsent(set.exerciseId, () => []).add(set);
    }
    return map;
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0 ? '$m 分 $sec 秒' : '$sec 秒';
  }

  void _editWorkout(BuildContext context, WidgetRef ref, WorkoutRepository repo) async {
    final workout = await repo.getById(workoutId);
    if (workout == null || !context.mounted) return;

    // 为每个 set 创建编辑控制器
    final controllers = <int, _SetEditCtrl>{};
    for (final s in workout.sets) {
      controllers[s.id] = _SetEditCtrl(
        reps: TextEditingController(text: s.reps?.toString() ?? ''),
        weight: TextEditingController(text: s.weightKg?.toString() ?? ''),
      );
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        appBar: AppBar(
          title: const Text('编辑训练记录'),
          actions: [
            TextButton(
              onPressed: () async {
                final newSets = <NewSetData>[];
                for (final s in workout.sets) {
                  final ctrl = controllers[s.id]!;
                  newSets.add(NewSetData(
                    exerciseId: s.exerciseId,
                    setNumber: s.setNumber,
                    reps: int.tryParse(ctrl.reps.text),
                    weightKg: double.tryParse(ctrl.weight.text),
                    durationSec: s.durationSec,
                    isWarmup: s.isWarmup,
                  ));
                }
                await repo.updateWorkout(id: workoutId, sets: newSets);
                ref.read(dashboardRefreshCount.notifier).state++;
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: workout.sets.length,
          itemBuilder: (context, index) {
            final s = workout.sets[index];
            final ctrl = controllers[s.id]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text('${s.setNumber}', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: ctrl.reps,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '次数', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: ctrl.weight,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: '重量 kg', isDense: true),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ));
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, WorkoutRepository repo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除训练记录'),
        content: const Text('确定要删除这条训练记录吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await repo.delete(workoutId);
              ref.read(dashboardRefreshCount.notifier).state++;
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _SetEditCtrl {
  final TextEditingController reps;
  final TextEditingController weight;
  _SetEditCtrl({required this.reps, required this.weight});
}

class _DetailData {
  final WorkoutEntity? workout;
  final Map<String, double> prs;
  const _DetailData({this.workout, this.prs = const {}});
}

Future<void> _shareWorkout(BuildContext context, WidgetRef ref,
    WorkoutRepository workoutRepo, dynamic exerciseRepo, int workoutId) async {
  final workout = await workoutRepo.getById(workoutId);
  if (workout == null || !context.mounted) return;

  final exercises = await exerciseRepo.getAll();
  final nameMap = {for (final e in exercises) e.id: e.name};
  final exerciseNames = workout.sets
    .map((s) => nameMap[s.exerciseId] ?? '')
    .where((n) => n.isNotEmpty)
    .toSet()
    .cast<String>();

  final userSettings = ref.read(userSettingsProvider).valueOrNull;
  String? bmiInfo;
  // Get latest weight for BMI
  final bodyRepo = ref.read(bodyMetricRepoProvider);
  final latestMetric = await bodyRepo.getLatest();
  if (latestMetric != null && userSettings?.heightCm != null) {
    final bmi = userSettings!.bmi(latestMetric.weightKg);
    if (bmi != null) {
      bmiInfo = 'BMI ${bmi.toStringAsFixed(1)} · ${UserSettingsEntity.bmiLevelLabels[UserSettingsEntity.bmiLevel(bmi)]}';
    }
  }

  if (!context.mounted) return;
  await shareWorkoutCard(context, workout, exerciseNames, bmiInfo);
}

/// 生成分享图片的实际函数（从详情页调用时workout已加载）
Future<void> shareWorkoutCard(BuildContext context, WorkoutEntity workout,
    Set<String> exerciseNames, String? bmiInfo) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 200));

    final bgPaint = Paint()..color = const Color(0xFF1A1A2E);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 200), bgPaint);

    _drawText(canvas, '🔥 FitTrack 训练记录', 20, 30, 22, Colors.white, bold: true);
    _drawText(canvas, DateFormat('yyyy年M月d日 HH:mm').format(workout.date), 20, 56, 13, Colors.white70);
    canvas.drawLine(const Offset(20, 68), const Offset(380, 68),
      Paint()..color = Colors.white24..strokeWidth = 0.5);
    _drawText(canvas, '完成 ${exerciseNames.length} 个动作 · ${workout.totalSets} 组', 20, 90, 15, Colors.white, bold: true);
    if (workout.durationSec != null) {
      _drawText(canvas, '训练时长: ${workout.durationSec! ~/ 60} 分 ${workout.durationSec! % 60} 秒', 20, 112, 13, Colors.white70);
    }
    if (bmiInfo != null) {
      _drawText(canvas, bmiInfo, 20, 130, 13, Colors.cyanAccent);
    }
    _drawText(canvas, '💪 让每一次训练都有记录', 20, 170, 12, Colors.white38);

    final picture = recorder.endRecording();
    final img = await picture.toImage(400, 200);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/fittrack_share_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles([XFile(file.path)], text: '我的 FitTrack 训练记录 💪');
  } catch (e) {
    debugPrint('Share failed: $e');
  }
}

void _drawText(Canvas canvas, String text, double x, double y, double fontSize, Color color, {bool bold = false}) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: TextAlign.left,
    fontSize: fontSize,
    textDirection: ui.TextDirection.ltr,
  ))
    ..pushStyle(ui.TextStyle(
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    ))
    ..addText(text);
  final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 360));
  canvas.drawParagraph(paragraph, Offset(x, y));
}
