import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/body_log/data/body_metric_repository_impl.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_metric_page.dart';

/// 体重页录入 → 首页「今日打卡」联动
///
/// 报障：在体重页输入体重保存后，主控页不显示新体重、体重打卡块不变橙、
/// 今日打卡数不变。根因是录入回调只 invalidate 了体重页自己的 provider，
/// 首页/趋势页各自缓存的聚合数据没人刷。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    // 保存后会弹「体重已记录」本地通知，测试环境没有平台实现，兜住通道
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => true,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
    await db.close();
  });

  testWidgets('保存体重后，首页数据源立刻能看到今日记录', (tester) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // 首页此前已经渲染过一次 —— 缓存里是「今天还没记录」
    final before = await container.read(dashboardDataProvider.future);
    expect(before.todayMetric, isNull, reason: '前置条件：库里今天没有体重');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const BodyMetricPage()),
    ));
    await tester.pumpAndSettle();

    final weightField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.suffixText == '斤',
    );
    expect(weightField, findsOneWidget);

    await tester.enterText(weightField, '120'); // 斤
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    // 数据确实落库（120 斤 = 60 kg）
    final stored = await BodyMetricRepositoryImpl(db).getLatest();
    expect(stored, isNotNull);
    expect(stored!.weightKg, closeTo(60, 0.001));

    // 首页缓存必须被刷新：今日打卡能拿到记录，体重块才会变橙
    final after = await container.read(dashboardDataProvider.future);
    expect(after.todayMetric, isNotNull,
        reason: '保存后 dashboardDataProvider 必须被 invalidate');
    expect(after.todayMetric!.weightKg, closeTo(60, 0.001));
    expect(after.latestMetric!.weightKg, closeTo(60, 0.001));
  });
}
