import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fakes/workout_harness.dart';

/// T-13 全库只有**一处**训练记录列表；T-18 老深链不白屏
///
/// 为什么用源码守卫：这类问题不是"某段逻辑错了"，而是"有人又加了一份"。
/// 单元测试拦不住新增的第二份列表，只有扫描源码才拦得住。
void main() {
  test('T-13 `HistorySegment` 类型在 lib/ 与 test/ 里都不存在', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'test']) {
      for (final f in Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // 守卫自己会提到这个名字（否则没法写断言）
          .where((f) => !f.path.endsWith('workout_single_list_guard_test.dart'))) {
        final text = f.readAsStringSync();
        // 只看代码：注释里提到"历史分段已删除"是必要的
        final code = text
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (code.contains('HistorySegment') ||
            code.contains('history_segment.dart')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('T-13 训练页没有第三段（分段值只有 0 / 1）', () {
    final source = File(
            'lib/features/workout/presentation/pages/quick_start_page.dart')
        .readAsStringSync();
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('value: 2'), isFalse, reason: '第三段（历史）已下线');
    expect(code.contains("'历史'"), isFalse);
  });

  test('T-13 只有记录页 **watch** workoutHistoryProvider（单一渲染源）', () {
    // 只数 watch：invalidate 的写入方可以有多个（AI 工具、训练结束、删除记录）
    final watchers = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (f.readAsStringSync().contains('watch(workoutHistoryProvider')) {
        watchers.add(f.path);
      }
    }
    expect(watchers, hasLength(1),
        reason: '同一份数据两套渲染会让口径分叉：${watchers.join(', ')}');
    expect(watchers.single, contains('workout_records_page.dart'));
  });

  test('路由顺序：`/workout/records` 声明在 `/workout/:id` 之前（T-18 的孪生坑）', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final recordsAt = source.indexOf("path: '/workout/records'");
    final idAt = source.indexOf("path: '/workout/:id'");
    expect(recordsAt, greaterThan(0));
    expect(idAt, greaterThan(0));
    expect(recordsAt, lessThan(idAt),
        reason: 'go_router 按声明顺序匹配，写反了会点进「无效的训练ID」');
    // stats / active / template-edit 也必须排在 :id 之前
    for (final path in ['/workout/stats', '/workout/active', '/workout/template-edit']) {
      expect(source.indexOf("path: '$path'"), lessThan(idAt), reason: path);
    }
  });

  test('老深链 `/workout/quick-start` 仍然存在且 redirect 到 /workout', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    expect(source, contains("path: '/workout/quick-start'"));
    expect(source, contains("redirect: (_, __) => '/workout'"));
  });

  testWidgets('T-18 go(/workout/quick-start) 最终落在 /workout（不白屏）',
      (tester) async {
    final harness = WorkoutHarness();
    addTearDown(harness.dispose);

    await tester
        .pumpWidget(harness.app(initialLocation: '/workout/quick-start'));
    await tester.pump();
    await tester.pump();

    expect(harness.location, '/workout');
    expect(find.text('训练'), findsOneWidget);
  });

  test('`/workout` 路由渲染的是训练页，不是记录页', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final workoutTabAt = source.indexOf("path: '/workout',");
    expect(workoutTabAt, greaterThan(0));
    final block = source.substring(workoutTabAt, workoutTabAt + 200);
    expect(block, contains('QuickStartPage'));
    expect(block.contains('WorkoutListPage'), isFalse,
        reason: 'WorkoutListPage 已删除，Tab 必须是即时训练页');
  });
}
