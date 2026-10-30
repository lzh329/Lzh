import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/exercise_item_editor.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 「编辑动作」弹窗的两种形态：
/// - 有氧：只有时长一格，返回 sets=1 / reps=null / durationSec=分钟×60
/// - 力量：组×次，静力动作组×秒（回归）
void main() {
  EditItem item({
    int sets = 3,
    int? reps = 12,
    int? durationSec,
  }) =>
      EditItem(
        exerciseId: 1,
        name: '平板支撑',
        category: 'strength',
        sets: sets,
        reps: reps,
        durationSec: durationSec,
      );

  /// 弹出一个按钮，点它打开弹窗，并记录返回值
  Future<EditItem?> open(
    WidgetTester tester,
    EditItem seed, {
    bool isCardio = false,
    required Future<void> Function(WidgetTester) interact,
  }) async {
    EditItem? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showExerciseItemEditor(ctx,
                    item: seed, isCardio: isCardio);
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

  testWidgets('有氧：只显示时长一格，填 15 分钟 → (1, null, 900)', (tester) async {
    final r = await open(
      tester,
      item(reps: null, durationSec: 600),
      isCardio: true,
      interact: (t) async {
        // 不该出现组数/次数两格
        expect(find.text('组数'), findsNothing);
        expect(find.text('每组次数'), findsNothing);
        expect(find.text('时长（分钟）'), findsOneWidget);

        await t.enterText(find.byType(TextField), '15');
        await t.tap(find.text('确定'));
      },
    );

    expect(r, isNotNull);
    expect(r!.sets, 1);
    expect(r.reps, isNull);
    expect(r.durationSec, 900, reason: '15 分钟 = 900 秒');
  });

  testWidgets('有氧：标题标明类型（编辑动作 · 有氧）', (tester) async {
    await open(
      tester,
      item(reps: null, durationSec: 600),
      isCardio: true,
      interact: (t) async {
        expect(find.text('编辑动作 · 有氧'), findsOneWidget);
        await t.tap(find.text('取消'));
      },
    );
  });

  testWidgets('力量回归：普通动作仍是 组数 + 每组次数', (tester) async {
    final r = await open(
      tester,
      item(sets: 3, reps: 12),
      interact: (t) async {
        expect(find.text('组数'), findsOneWidget);
        expect(find.text('每组次数'), findsOneWidget);
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.sets, 3);
    expect(r.reps, 12);
    expect(r.durationSec, isNull);
  });

  testWidgets('力量回归：静力动作是 组数 + 每组秒数', (tester) async {
    final r = await open(
      tester,
      item(sets: 2, reps: null, durationSec: 30),
      interact: (t) async {
        expect(find.text('每组时长（秒）'), findsOneWidget);
        expect(find.text('每组次数'), findsNothing);
        await t.tap(find.text('确定'));
      },
    );

    expect(r!.sets, 2);
    expect(r.reps, isNull);
    expect(r.durationSec, 30);
  });
}
