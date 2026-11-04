import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/workout_week_strip.dart';

import 'fakes/workout_harness.dart';

/// T-1 ~ T-5：训练 Tab 只回答"现在练什么"
void main() {
  late WorkoutHarness harness;

  setUp(() => harness = WorkoutHarness());
  tearDown(() => harness.dispose());

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(harness.app(initialLocation: '/workout'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('T-1 是即时训练页：标题「训练」，没有周条', (tester) async {
    await pumpHome(tester);

    expect(find.text('训练'), findsOneWidget);
    expect(find.byType(WorkoutWeekStrip), findsNothing,
        reason: '周条只属于记录页');
    expect(find.text('模板'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
  });

  testWidgets('T-2 只有两段：模板 / 计划，「历史」为 0', (tester) async {
    await pumpHome(tester);

    expect(find.text('模板'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('历史'), findsNothing, reason: '历史分段本期下线（决策 12）');
    // 分段控件只有两个选项
    final segmented = tester.widget<SegmentedButton<int>>(
        find.byType(SegmentedButton<int>));
    expect(segmented.segments, hasLength(2));
  });

  testWidgets('T-3 右上角两个 action：训练记录 / 新建模板，点记录进 /workout/records',
      (tester) async {
    await pumpHome(tester);

    expect(find.byTooltip('训练记录'), findsOneWidget);
    expect(find.byTooltip('新建模板'), findsOneWidget);

    await tester.tap(find.byTooltip('训练记录'));
    await tester.pumpAndSettle();

    expect(harness.location, '/workout/records');
    expect(find.text('训练记录'), findsOneWidget, reason: '记录页 AppBar 标题');
  });

  testWidgets('T-4 没有 FAB（新建模板只走 AppBar）', (tester) async {
    await pumpHome(tester);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('T-5 不存在时长选择器（10/5/23 分钟三档）', (tester) async {
    await pumpHome(tester);

    // 不出现「10 分钟」「5 分钟」「23 分钟」这类档位按钮
    for (final label in ['10 分钟', '5 分钟', '23 分钟', '10分钟', '5分钟', '23分钟']) {
      expect(find.text(label), findsNothing, reason: '本期不发明时长选择器（决策 9）');
    }
    // 也没有任何"按时长筛选"的控件 key
    expect(find.byKey(const ValueKey('duration-picker')), findsNothing);
  });
}
