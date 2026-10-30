import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';

/// 动作库「改分类」的数据侧行为：内置动作也能改、部位不被覆盖
void main() {
  late AppDatabase db;
  late ExerciseRepositoryImpl repo;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = ExerciseRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  test('内置动作改分类：落库生效，muscleGroup 原值保留', () async {
    final all = await repo.getAll();
    final builtin = all.firstWhere((e) => !e.isCustom);
    expect(builtin.category, isNotEmpty);

    await repo.update(ExerciseEntity(
      id: builtin.id,
      name: builtin.name,
      category: 'cardio',
      muscleGroup: builtin.muscleGroup,
      isCustom: builtin.isCustom,
      defaultReps: builtin.defaultReps,
      defaultWeightKg: builtin.defaultWeightKg,
      defaultDurationSec: builtin.defaultDurationSec,
    ));

    final after = await repo.getById(builtin.id);
    expect(after!.category, 'cardio', reason: '内置动作也要能改分类');
    expect(after.muscleGroup, builtin.muscleGroup, reason: '部位不再可编辑，旧值必须保留');
    expect(after.isCustom, isFalse, reason: '改分类不能把它变成自定义动作');
  });

  test('自定义动作可改分类，且仍可删除', () async {
    final created = await repo.create('自建动作', 'strength', null);
    final id = created.id;
    await repo.update(ExerciseEntity(
      id: id,
      name: '自建动作',
      category: 'stretch',
      muscleGroup: null,
      isCustom: true,
    ));
    expect((await repo.getById(id))!.category, 'stretch');

    await repo.delete(id);
    expect(await repo.getById(id), isNull);
  });
}
