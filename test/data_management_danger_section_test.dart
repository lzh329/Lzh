import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/settings/presentation/widgets/data_management_danger_section.dart';

/// 「清除所有数据」是不可撤销操作，和「恢复数据库」还挨在同一页。
/// 这里只测一条：**没逐字打出「清除」就不能确认**。
void main() {
  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: DataManagementDangerSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('入口文案点明"先备份再清空"', (tester) async {
    await pumpSection(tester);
    expect(find.text('危险操作'), findsOneWidget);
    expect(find.text('清除所有数据'), findsOneWidget);
    expect(find.text('先自动备份，再清空你的记录与照片'), findsOneWidget);
  });

  testWidgets('必须逐字输入「清除」才能确认，输错就点不动', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.text('清除所有数据'));
    await tester.pumpAndSettle();

    // 弹窗里也要把后果写清楚（照片/设置/饮食等全部清空）
    expect(find.textContaining('无法撤销'), findsOneWidget);
    expect(find.textContaining('照片'), findsWidgets);
    expect(find.textContaining('内置训练模板'), findsOneWidget,
        reason: '内置字典保留这件事必须写进弹窗，否则用户会以为"回到出厂"');

    FilledButton confirmButton() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '清除'));

    expect(confirmButton().onPressed, isNull, reason: '空输入时确认按钮必须禁用');

    await tester.enterText(find.byType(TextField), '清');
    await tester.pump();
    expect(confirmButton().onPressed, isNull, reason: '少一个字也不行');

    // 逐字相等：前后带空格不算（不是 trim 之后比较）
    await tester.enterText(find.byType(TextField), ' 清除 ');
    await tester.pump();
    expect(confirmButton().onPressed, isNull, reason: '多一个空格也不算逐字输入');

    await tester.enterText(find.byType(TextField), '清除');
    await tester.pump();
    expect(confirmButton().onPressed, isNotNull);
  });

  testWidgets('取消后什么都不做', (tester) async {
    await pumpSection(tester);
    await tester.tap(find.text('清除所有数据'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}
