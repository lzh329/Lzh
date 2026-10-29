import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/exercise/data/exercise_repository_impl.dart';

/// 动作搜索回归测试（新建模板页「添加动作」弹窗的数据源）
///
/// 为什么是仓储级而不是 widget test：底部弹窗在 widget test 里需要
/// 真实的 MediaQuery + 滚动容器 + 异步 IO 三重配合，写出来脆弱且慢；
/// 这里要保证的核心行为是「输入即缩小结果集、空输入回落全量」，
/// 落在 search() 上验证最稳。UI 层只是把 onChanged 直接接到这个方法。
void main() {
  late AppDatabase db;
  late ExerciseRepositoryImpl repo;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = ExerciseRepositoryImpl(db);
    // 种子动作库里已有一批动作（深蹲 / 平板支撑…）
  });

  tearDown(() async => db.close());

  test('空输入走 getAll，能拿到种子动作', () async {
    final all = await repo.getAll();
    expect(all, isNotEmpty);
  });

  test('输入关键字只返回名字匹配的动作', () async {
    final all = await repo.getAll();
    final target = all.first.name;
    final hit = await repo.search(target.substring(0, 1));
    expect(hit, isNotEmpty);
    expect(hit.every((e) => e.name.contains(target.substring(0, 1))), isTrue);
    expect(hit.length, lessThanOrEqualTo(all.length));
  });

  test('搜不到时返回空列表（UI 据此显示空态文案）', () async {
    final miss = await repo.search('这个动作绝对不存在xyz');
    expect(miss, isEmpty);
  });
}
