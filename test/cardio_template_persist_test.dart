import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 混排模板落库（真内存库）：深蹲 3×15 + 跳绳 3×5 分钟
void main() {
  late AppDatabase db;
  late WorkoutTemplateRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = WorkoutTemplateRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  test('混排：力量行写 reps、有氧行写 durationSec，模板类型派生为 cardio', () async {
    final squat = await db.into(db.exercises).insert(
          ExercisesCompanion.insert(name: '深蹲', category: 'strength'),
        );
    final rope = await db.into(db.exercises).insert(
          ExercisesCompanion.insert(name: '跳绳', category: 'cardio'),
        );

    final derived = deriveTemplateType(['strength', 'cardio']);
    final id = await repo.create(
      name: '混排训练',
      difficulty: '入门',
      focus: '全身',
      type: derived,
      minutes: 20,
      items: [
        TemplateItemInput(
            exerciseId: squat,
            targetSets: 3,
            targetReps: 15,
            targetDurationSec: null),
        TemplateItemInput(
            exerciseId: rope,
            targetSets: 3,
            targetReps: null,
            targetDurationSec: cardioSeconds(5)),
      ],
    );

    final t = await repo.getById(id);
    expect(t!.type, 'cardio', reason: '含任一有氧动作 → 模板判为有氧');
    expect(t.items, hasLength(2));
    final withReps = t.items.firstWhere((i) => i.targetReps != null);
    final withTime = t.items.firstWhere((i) => i.targetReps == null);
    expect(withReps.targetSets, 3);
    expect(withReps.targetReps, 15);
    expect(withTime.targetDurationSec, 300, reason: '5 分钟 = 300 秒');
  });

  test('纯力量模板 → strength，静力动作仍写 durationSec（回归）', () async {
    final plank = await db.into(db.exercises).insert(
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
      type: deriveTemplateType(['strength']),
      minutes: 10,
      items: [
        TemplateItemInput(
            exerciseId: plank,
            targetSets: 3,
            targetReps: null,
            targetDurationSec: 60),
      ],
    );

    final t = await repo.getById(id);
    expect(t!.type, 'strength');
    expect(t.items.single.targetSets, 3);
    expect(t.items.single.targetReps, isNull);
    expect(t.items.single.targetDurationSec, 60);
  });

  test('空模板派生为 strength', () {
    expect(deriveTemplateType(const []), 'strength');
  });
}
