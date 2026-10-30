import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('浅色主题启用 Material 3 且亮度正确', () {
      final theme = AppTheme.light;
      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('分类的颜色 / 标签 / 图标三者键集合一致', () {
      final colorKeys = AppTheme.categoryColors.keys.toSet();
      expect(AppTheme.categoryLabels.keys.toSet(), colorKeys);
      expect(AppTheme.categoryIcons.keys.toSet(), colorKeys);
      expect(
          colorKeys, containsAll(['strength', 'cardio', 'stretch']));
    });
  });

  testWidgets('应用主题可正常渲染组件', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(child: Text('简瘦')),
        ),
      ),
    );

    expect(find.text('简瘦'), findsOneWidget);
  });
}
