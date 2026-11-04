import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/ai/presentation/pages/ai_coach_settings_page.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_coach_settings_widgets.dart';
import 'package:fittrack/features/settings/presentation/pages/settings_page.dart';

/// 教练设定页按三组重排（模型 / 行为 / 声音），并把语音入口从系统设置迁过来
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.withExecutor(NativeDatabase.memory()));
  tearDown(() async => db.close());

  ProviderContainer buildContainer() {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget host(ProviderContainer c, Widget child) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: child),
      );

  /// 把测试视口调高，让 ListView 一次把全部组建出来
  /// （否则懒构建会影响"顺序"与"存在性"断言）
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('三个组标题存在，且顺序是 模型 → 行为 → 声音', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
        host(buildContainer(), const AiCoachSettingsPage()));
    await tester.pumpAndSettle();

    // 用组标题组件定位：「模型」这种词在配置卡里也可能出现
    final model = find.widgetWithText(AiCoachGroupTitle, '模型');
    final behavior = find.widgetWithText(AiCoachGroupTitle, '行为');
    final voice = find.widgetWithText(AiCoachGroupTitle, '声音');
    expect(model, findsOneWidget);
    expect(behavior, findsOneWidget);
    expect(voice, findsOneWidget);

    final yModel = tester.getTopLeft(model).dy;
    final yBehavior = tester.getTopLeft(behavior).dy;
    final yVoice = tester.getTopLeft(voice).dy;
    expect(yModel, lessThan(yBehavior), reason: '模型组要在行为组上面');
    expect(yBehavior, lessThan(yVoice), reason: '行为组要在声音组上面');
  });

  testWidgets('顶部有「嘎教练能做什么」入口', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
        host(buildContainer(), const AiCoachSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('嘎教练能做什么'), findsOneWidget);
    expect(find.text('看看它有哪些能力'), findsOneWidget);
  });

  testWidgets('声音组里有语音教练入口', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
        host(buildContainer(), const AiCoachSettingsPage()));
    await tester.pumpAndSettle();

    // 滚到底部才看得到声音组
    await tester.scrollUntilVisible(find.text('语音教练'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('语音教练'), findsOneWidget);
  });

  testWidgets('系统设置页不再有「语音教练」（避免两个入口）', (tester) async {
    await tester.pumpWidget(host(buildContainer(), const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('语音教练'), findsNothing);
    // 页面本身渲染出来了（防止误删整页导致"没有语音教练"这种假绿）
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
