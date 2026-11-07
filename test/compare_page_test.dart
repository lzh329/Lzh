import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/body_log/presentation/pages/body_compare_page.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_overlay.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_panel.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_review_launcher.dart';

/// 对比页：任意日期选择 / 叠加滑动 / 体重缺失不显示 / 点评提示词不编造
void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('fittrack_compare_test');
  });

  tearDown(() async {
    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  File img(String name) =>
      File(p.join(tmp.path, name))..writeAsStringSync('img');

  Future<Photo> seed(DateTime date, {double? weightKg}) async {
    if (weightKg != null) {
      await db.into(db.bodyMetrics).insert(BodyMetricsCompanion.insert(
            date: date,
            weightKg: weightKg,
          ));
    }
    final id = await db.into(db.photos).insert(PhotosCompanion.insert(
          date: date,
          filePath: img('${date.millisecondsSinceEpoch}.jpg').path,
          category: const Value(null),
        ));
    return (db.select(db.photos)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> pumpCompare(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const BodyComparePage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('默认取最早 vs 最新，且两侧都能换', (tester) async {
    await seed(DateTime(2026, 9, 1), weightKg: 70);
    await seed(DateTime(2026, 10, 1), weightKg: 68);
    await seed(DateTime(2026, 11, 1), weightKg: 66);
    await pumpCompare(tester);

    expect(find.byType(ComparePhotoPanel), findsNWidgets(2));

    // 换左图 → 选最新那张
    await tester.tap(find.text('换左图'));
    await tester.pumpAndSettle();
    expect(find.text('选择较早的那张'), findsOneWidget);
    await tester.tap(find.text('2026年10月1日'));
    await tester.pumpAndSettle();

    // 左早右晚：左图变为 10-01，仍在右图之前
    final panels = tester
        .widgetList<ComparePhotoPanel>(find.byType(ComparePhotoPanel))
        .toList();
    expect(panels.first.photo.date, DateTime(2026, 10, 1));
    expect(panels.first.photo.date.isBefore(panels.last.photo.date), isTrue,
        reason: '左早右晚不能被选反');
  });

  testWidgets('切到叠加滑动模式，分割线可拖动', (tester) async {
    await seed(DateTime(2026, 9, 1), weightKg: 70);
    await seed(DateTime(2026, 11, 1), weightKg: 66);
    await pumpCompare(tester);

    await tester.tap(find.byTooltip('滑动对比'));
    await tester.pumpAndSettle();
    expect(find.byType(CompareOverlay), findsOneWidget);

    final before = tester.widget<CompareOverlay>(find.byType(CompareOverlay)).split;
    await tester.drag(find.byType(CompareOverlay), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final after = tester.widget<CompareOverlay>(find.byType(CompareOverlay)).split;
    expect(after, lessThan(before), reason: '向左拖动应缩小左图占比');
  });

  testWidgets('缺体重记录时，不显示「体重变化」', (tester) async {
    await seed(DateTime(2026, 9, 1)); // 无体重
    await seed(DateTime(2026, 11, 1), weightKg: 66);
    await pumpCompare(tester);

    expect(find.text('时间跨度'), findsOneWidget);
    expect(find.text('体重变化'), findsNothing,
        reason: '只有一侧有记录时不能猜变化');
  });

  test('点评提示词：带真实日期与体重，缺失时明说未记录并禁止推测', () {
    final both = buildCompareReviewPrompt(
      beforeDate: DateTime(2026, 9, 1),
      afterDate: DateTime(2026, 11, 1),
      beforeJin: 140,
      afterJin: 132,
    );
    expect(both.contains('116 天'), isFalse); // 61 天
    expect(both.contains('61 天'), isTrue);
    expect(both.contains('140.0 斤 → 132.0 斤'), isTrue);
    expect(both.contains('不要推测或编造'), isTrue);

    final missing = buildCompareReviewPrompt(
      beforeDate: DateTime(2026, 9, 1),
      afterDate: DateTime(2026, 11, 1),
      beforeJin: null,
      afterJin: 132,
    );
    expect(missing.contains('前一张未记录'), isTrue);
    expect(missing.contains('132.0 斤'), isTrue);
  });
}
