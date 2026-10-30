import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 有氧模板落库形态（真内存库）：
/// - 动作行：sets=1 / durationSec=分钟×60 / reps=null
/// - 力量静力动作：仍写 durationSec（回归）
void main() {
  late AppDatabase db;
  late WorkoutTemplateRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = WorkoutTemplateRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  test('有氧：动作按 cardioItemValues 落库，reps 为 null', () async {
    final exerciseId = await db.into(db.exercises).insert(
          ExercisesCompanion.insert(
            name: '慢跑',
            category: 'cardio',
          ),
        );

    final v = cardioItemValues(45); // 45 分钟
    final id = await repo.create(
      name: '45 分钟慢跑',
      difficulty: '入门',
      focus: '全身',
      type: 'cardio',
      minutes: 45,
      items: [
        TemplateItemInput(
          exerciseId: exerciseId,
          targetSets: v.sets,
          targetReps: v.reps,
          targetDurationSec: v.durationSec,
        ),
      ],
    );

    final t = await repo.getById(id);
    expect(t!.type, 'cardio');
    expect(t.isCardio, isTrue);
    expect(t.minutes, 45, reason: '有氧的总时长就是 minutes');
    final item = t.items.single;
    expect(item.targetSets, 1);
    expect(item.targetReps, isNull, reason: '有氧没有"次数"');
    expect(item.targetDurationSec, 45 * 60);
  });

  test('力量回归：静力动作仍写 durationSec，且 type=strength', () async {
    final exerciseId = await db.into(db.exercises).insert(
          ExercisesCompanion.insert(
            name: '平板支撑',
            category: 'strength',
            defaultDurationSec: const Value(60),
          ),
        );

    final id = await repo.create(
      name: '核心静力',
      difficulty: '入门',
      focus: '全身',
      type: 'strength',
      minutes: 10,
      items: [
        TemplateItemInput(
          exerciseId: exerciseId,
          targetSets: 3,
          targetReps: null,
          targetDurationSec: 60,
        ),
      ],
    );

    final t = await repo.getById(id);
    expect(t!.type, 'strength');
    expect(t.items.single.targetSets, 3);
    expect(t.items.single.targetReps, isNull);
    expect(t.items.single.targetDurationSec, 60);
  });
}
