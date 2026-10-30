import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/template_basics_section.dart';

/// 编辑页不再有「类型」选择器：模板类型由动作构成派生，用户不需要手选
void main() {
  testWidgets('基础信息区没有「类型」分段控件，只有统一的预计时长滑块', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TemplateBasicsSection(
          nameCtrl: TextEditingController(text: '测试模板'),
          descCtrl: TextEditingController(),
          difficulty: '入门',
          minutes: 15,
          onDifficulty: (_) {},
          onMinutes: (_) {},
        ),
      ),
    ));

    // 不再有类型二选一
    expect(find.text('类型'), findsNothing);
    expect(find.text('力量'), findsNothing);
    expect(find.text('有氧'), findsNothing);
    // 统一的「预计时长」滑块回来了
    expect(find.text('预计时长'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    // 名称与难度仍在
    expect(find.text('模板名称'), findsOneWidget);
    expect(find.text('难度'), findsOneWidget);
  });
}
