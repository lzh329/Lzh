import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/sick_day_banner.dart';
import 'package:fittrack/features/settings/presentation/widgets/sick_day_toggle_tile.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> seed({
    double? setsScale,
    int? calorieTargetOverride,
    bool reminderPaused = false,
    String source = 'user',
  }) {
    return DailyOverrideRepository(db).upsert(
      date: DateTime.now(),
      setsScale: setsScale,
      calorieTargetOverride: calorieTargetOverride,
      reminderPaused: reminderPaused,
      source: source,
    );
  }

  Widget buildHost(Widget child) {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  group('T03-C1 / C2 / C5 横幅出现与文案', () {
    testWidgets('当天没有覆盖 → 横幅不渲染', (WidgetTester tester) async {
      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(find.text('生病模式'), findsNothing);
    });

    testWidgets('T03-C1 生效时横幅出现（source=user 与 ai_health 共用同一状态）',
        (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true, source: 'ai_health');

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(find.text('生病模式'), findsOneWidget);
    });

    testWidgets('T03-C2 横幅写明「仅今天有效，明天自动恢复」', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true);

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(find.text('仅今天有效，明天自动恢复'), findsOneWidget,
          reason: '不写这句，用户会把临时状态当成持久设置，第二天以为数据错了');
    });

    testWidgets('T03-C5 横幅上有「撤销」按钮', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true);

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(find.text('撤销'), findsOneWidget);
    });

    testWidgets('文案只说实际改了的东西，没有的别编', (WidgetTester tester) async {
      await seed(setsScale: 0.5);

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(
        find.text('训练组数按 50% 执行'),
        findsOneWidget,
      );
      expect(
        find.text('今天训练和称重提醒都不响'),
        findsNothing,
        reason: '这次没暂停提醒，不该写上去',
      );
    });

    testWidgets('三个字段都有时逐条列出', (WidgetTester tester) async {
      await seed(
        setsScale: 0.5,
        calorieTargetOverride: 2200,
        reminderPaused: true,
      );

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();

      expect(
        find.text('训练组数按 50% 执行 · 热量目标放宽到 2200 千卡 · '
            '今天训练和称重提醒都不响'),
        findsOneWidget,
      );
    });
  });

  group('T03-C6 一键撤销', () {
    testWidgets('点一次「撤销」横幅立刻消失，且不弹二次确认', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true);

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();
      expect(find.text('生病模式'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing,
          reason: '撤销是回到安全状态，要二次确认就是把救回数据做得比改数据还难');
      expect(find.text('生病模式'), findsNothing);
      expect(find.text('仅今天有效，明天自动恢复'), findsNothing);
    });

    testWidgets('撤销后数据库里那一行也真的没了', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true);

      await tester.pumpWidget(buildHost(const SickDayBanner()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();

      expect(
        await DailyOverrideRepository(db).getByDate(DateTime.now()),
        isNull,
      );
    });
  });

  group('T03-C8 手动开关与 AI 写入共用同一 UI 状态', () {
    testWidgets('设置页开关反映 AI 写的那一行', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true, source: 'ai_health');

      await tester.pumpWidget(buildHost(const SickDayToggleTile()));
      await tester.pumpAndSettle();

      expect(find.text('今天不舒服'), findsOneWidget);
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
        reason: '看不出是谁开的，但看得出已生效',
      );
    });

    testWidgets('手动打开开关 → 写库且 source=user（不碰任何 AI provider）',
        (WidgetTester tester) async {
      await tester.pumpWidget(buildHost(const SickDayToggleTile()));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final o = await DailyOverrideRepository(db).getByDate(DateTime.now());
      expect(o, isNotNull);
      expect(o!.source, 'user');
      expect(o.setsScale, closeTo(0.5, 1e-9));
      expect(o.reminderPaused, isTrue);
      expect(o.calorieTargetOverride, isNull,
          reason: '手动开关不碰热量目标 —— 那需要知道用户的全局目标');
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('手动关闭开关 → 行被删掉', (WidgetTester tester) async {
      await seed(setsScale: 0.5, reminderPaused: true, source: 'user');

      await tester.pumpWidget(buildHost(const SickDayToggleTile()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        await DailyOverrideRepository(db).getByDate(DateTime.now()),
        isNull,
      );
    });
  });
}
