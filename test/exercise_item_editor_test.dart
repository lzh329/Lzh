import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/exercise_item_editor.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 「编辑动作」弹窗：形态由**动作分类**决定，同一模板可混排三类动作
void main() {
  EditItem item({
    required String category,
    int sets = 3,
    int? reps = 12,
    int? durationSec,
  }) =>
      EditItem(
        exerciseId: 1,
        name: '哑铃深蹲',
        category: category,
        sets: sets,
        reps: reps,
        durationSec: durationSec,
      );

  Future<EditItem?> open(
    WidgetTester tester,
    EditItem seed, {
    required Future<void> Function(WidgetTester) interact,
  }) async {
    EditItem? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showExerciseItemEditor(ctx, item: seed);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('有氧动作：组数 + 时长（分钟）→ (sets, null, 分钟×60)', (tester) async {
    final r = await open(
      tester,
      item(category: 'cardio', reps: null, durationSec: 600),
      interact: (t) async {
        expect(find.text('每组次数'), findsNothing);
        expect(find.text('时长（分钟）'), findsOneWidget);
        expect(find.textContaining('有氧'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, '5');
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.sets, 3, reason: '有氧也有组数：跳绳 3×5 分钟');
    expect(r.reps, isNull);
    expect(r.durationSec, 300);
  });

  testWidgets('力量动作：组数 + 每组次数 → (sets, reps, null)', (tester) async {
    final r = await open(
      tester,
      item(category: 'strength', reps: 12),
      interact: (t) async {
        expect(find.text('每组次数'), findsOneWidget);
        await t.enterText(find.byType(TextField).last, '15');
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.sets, 3);
    expect(r.reps, 15);
    expect(r.durationSec, isNull);
  });

  testWidgets('静力动作（无次数）：组数 + 秒 → (sets, null, 秒)', (tester) async {
    final r = await open(
      tester,
      item(category: 'strength', reps: null, durationSec: 45),
      interact: (t) async {
        expect(find.text('每组时长（秒）'), findsOneWidget);
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.sets, 3);
    expect(r.reps, isNull);
    expect(r.durationSec, 45);
  });

  testWidgets('拉伸动作：走秒，不走次数', (tester) async {
    final r = await open(
      tester,
      item(category: 'stretch', reps: null, durationSec: 60),
      interact: (t) async {
        expect(find.text('每组时长（秒）'), findsOneWidget);
        expect(find.text('每组次数'), findsNothing);
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.reps, isNull);
    expect(r.durationSec, 60);
  });
}
