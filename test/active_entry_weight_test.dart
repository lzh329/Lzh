import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/active_workout_entry_panel.dart';

/// 开练页输入面板：重量输入只给力量动作（v23 后 strength，含原 gym/bodyweight）
void main() {
  Future<void> pump(WidgetTester tester, String category) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActiveWorkoutEntryPanel(
          category: category,
          isTimed: category != 'strength',
          isResting: false,
          isLastSet: false,
          lastReps: null,
          lastWeight: null,
          lastDuration: null,
          targetReps: 12,
          targetDurationSec: null,
          targetWeightKg: null,
          weightController: TextEditingController(),
          repsController: TextEditingController(),
          durationController: TextEditingController(),
        ),
      ),
    ));
  }

  testWidgets('力量动作：出现重量输入框（可选，不强制）', (tester) async {
    await pump(tester, 'strength');
    expect(find.text('重量'), findsOneWidget);
  });

  testWidgets('有氧动作：不出现重量输入框', (tester) async {
    await pump(tester, 'cardio');
    expect(find.text('重量'), findsNothing);
  });

  testWidgets('拉伸动作：不出现重量输入框', (tester) async {
    await pump(tester, 'stretch');
    expect(find.text('重量'), findsNothing);
  });
}
