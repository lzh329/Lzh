import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/repositories/workout_template_repository.dart';
import 'package:fittrack/features/workout/domain/workout_log_draft.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_log_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_detail_page.dart';
import 'package:fittrack/features/workout/presentation/pages/workout_records_page.dart';
import 'package:fittrack/features/workout/presentation/widgets/workout_record_card.dart';

import 'fake_database.dart';

/// 「记一笔」纯记录模块：模板带出动作 + 填实际组次重 + 保存
void main() {
  late AppDatabase db;
  late GoRouter router;
  late int squatId;

  setUp(() async {
    db = fakeDatabase();
    squatId = await db.into(db.exercises).insert(
        ExercisesCompanion.insert(name: '深蹲', category: 'strength'));
    // 一个"我的模板"：深蹲 3 组 × 12 次
    await WorkoutTemplateRepositoryImpl(db).create(
      name: '我的腿',
      difficulty: '入门',
      focus: '全身',
      minutes: 20,
      items: [
        TemplateItemInput(exerciseId: squatId, targetSets: 3, targetReps: 12),
      ],
    );
  });

  tearDown(() async {
    await db.close();
  });

  String location() =>
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation;

  Widget host() {
    router = GoRouter(
      // 从记录页**push** 进来（真机上的路径），这样保存后的 pop 才有地方回
      initialLocation: '/workout/records',
      routes: [
        GoRoute(
          path: '/workout/records',
          builder: (_, __) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => router.push('/workout/log/new'),
                child: const Text('训练记录页'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/workout/log/new',
          builder: (_, __) => const WorkoutLogPage(),
        ),
      ],
    );
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> pumpLog(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('训练记录页')); // 记录页 →「记一笔」
    await tester.pumpAndSettle();
    await tester.pump(); // 模板列表
  }

  group('模板带出动作（T 核心：不是空白模式）', () {
    testWidgets('第一步只列模板，不出现动作编辑区', (tester) async {
      await pumpLog(tester);

      expect(find.text('记一笔 · 选模板'), findsOneWidget);
      expect(find.text('我的模板'), findsOneWidget);
      expect(find.text('我的腿'), findsOneWidget);
      expect(find.text('保存这一笔'), findsNothing,
          reason: '还没选模板，不该有保存按钮');
    });

    testWidgets('选模板 → 自动带出动作 + 组数次数默认值', (tester) async {
      await pumpLog(tester);

      await tester.tap(find.text('我的腿'));
      await tester.pump();

      expect(find.text('记一笔'), findsOneWidget);
      expect(find.text('深蹲'), findsOneWidget, reason: '动作清单来自模板');
      expect(find.text('3'), findsWidgets, reason: '组数默认取模板的 3');
      expect(find.text('12'), findsOneWidget, reason: '次数默认取模板的 12');
      expect(find.text('共 3 组'), findsOneWidget);
      expect(find.text('保存这一笔'), findsOneWidget);
    });

    testWidgets('组数 +1 → 「共 4 组」跟着变', (tester) async {
      await pumpLog(tester);
      await tester.tap(find.text('我的腿'));
      await tester.pump();

      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('sets')),
        matching: find.byIcon(Icons.add),
      ));
      await tester.pump();

      expect(find.text('共 4 组'), findsOneWidget);
      expect(find.text('4'), findsWidgets);
    });
  });

  group('保存', () {
    testWidgets('保存成功 → 回记录页，库里是一条 type=log、planId=null、note 空 的记录',
        (tester) async {
      await pumpLog(tester);
      await tester.tap(find.text('我的腿'));
      await tester.pump();

      await tester.tap(find.text('保存这一笔'));
      await tester.pump(); // 写库
      await tester.pump(); // pop
      await tester.pump();

      expect(location(), '/workout/records', reason: '保存后回记录页');

      final rows = await db.select(db.workouts).get();
      expect(rows, hasLength(1));
      final workout = rows.single;
      expect(workout.type, 'log');
      expect(workout.planId, isNull, reason: 'planId 为 null ⇒ 不算计划完成');
      expect(workout.type, 'log', reason: '补记的来源字段');
      expect(workout.note, isNull, reason: 'note 留给用户写备注，系统不占用');
      expect(workout.durationSec, isNull, reason: '补记没有计时');

      final sets = await db.select(db.workoutSets).get();
      expect(sets, hasLength(3), reason: '3 组 = 3 条 set');
      expect(sets.map((s) => s.setNumber).toList()..sort(), [1, 2, 3]);
      expect(sets.every((s) => s.reps == 12), isTrue);
      expect(sets.every((s) => s.isCompleted), isTrue);
      expect(sets.every((s) => !s.isWarmup), isTrue);
      expect(sets.every((s) => s.weightKg == null), isTrue,
          reason: '模板没有重量 ⇒ 不预填重量（避免假数据）');
    });

    testWidgets('带 ?date= 进入：补记落在那天，而不是今天（日期 bug 回归）', (tester) async {
      // 直接以带日期的路由进入（模拟记录页选中 11-01 后点「记一笔」）
      router = GoRouter(
        initialLocation: '/workout/log/new?date=2026-11-01',
        routes: [
          GoRoute(
            path: '/workout/log/new',
            builder: (_, __) => const WorkoutLogPage(),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('我的腿'));
      await tester.pump();
      await tester.tap(find.text('保存这一笔'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final rows = await db.select(db.workouts).get();
      final workout = rows.single;
      expect(workout.date.year, 2026);
      expect(workout.date.month, 11);
      expect(workout.date.day, 1, reason: '补记应落在记录页选中的那天，而不是今天');
    });

    testWidgets('删光动作 → 保存按钮不可点（空记录没有信息量）', (tester) async {
      await pumpLog(tester);
      await tester.tap(find.text('我的腿'));
      await tester.pump();

      await tester.tap(find.byTooltip('删掉这个动作'));
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: '一个动作都没有时不许保存');
      expect(find.textContaining('加动作'), findsWidgets);
    });

    testWidgets('保存后记录页**立刻**出现这一条（走真实记录页，验证 invalidate）',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      // 这条用**真实记录页**做底层路由：它读的是 workoutHistoryProvider，
      // 保存后不重启就能看到卡片，才算"刷新入口"真的接上了。
      router = GoRouter(
        initialLocation: '/workout/records',
        routes: [
          GoRoute(
            path: '/workout/records',
            builder: (_, __) => const WorkoutRecordsPage(),
          ),
          GoRoute(
            path: '/workout/log/new',
            builder: (_, __) => const WorkoutLogPage(),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(WorkoutRecordCard), findsNothing, reason: '还没有记录');

      // AppBar 上的「记一笔」主按钮（本次新增的入口）
      await tester.tap(find.text('记一笔'));
      await tester.pumpAndSettle();
      expect(location(), '/workout/log/new');

      await tester.tap(find.text('我的腿'));
      await tester.pump();
      await tester.tap(find.text('保存这一笔'));
      // 这一页没有无限动画，可以放心 settle（转场 + 重建一起等完）
      await tester.pumpAndSettle();

      expect(location(), '/workout/records');
      expect(find.byType(WorkoutRecordCard), findsOneWidget,
          reason: '保存后记录页要立刻出现这一条（不需要重启）');
      expect(find.text('深蹲'), findsOneWidget);
      expect(find.text('补记'), findsOneWidget, reason: '补记记录要有轻标记');
    });
  });

  group('详情页：补记只显示「补记」，绝不漏内部值', () {
    testWidgets('type=log 的记录 → 详情页出现「补记」，且不含 log/free/plan 字样',
        (tester) async {
      await initializeDateFormatting('zh_CN');
      final id = await db.into(db.workouts).insert(WorkoutsCompanion.insert(
            date: DateTime.now(),
            type: 'log',
          ));
      await db.into(db.workoutSets).insert(WorkoutSetsCompanion.insert(
            workoutId: id,
            exerciseId: squatId,
            setNumber: 1,
            reps: const Value(12),
            isCompleted: const Value(true),
          ));

      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: WorkoutDetailPage(workoutId: id)),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      // 用户向标签在
      expect(find.text('补记'), findsOneWidget);

      // 内部值一个都不许出现在界面上（用户不该看到 log / free / plan）
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      for (final raw in ['log', 'free', 'plan']) {
        expect(
          texts.any((t) => t.toLowerCase() == raw),
          isFalse,
          reason: '界面出现了内部值「$raw」：$texts',
        );
      }
    });
  });

  group('草稿纯函数', () {
    WorkoutTemplateItemEntity item({
      int exerciseId = 1,
      String name = '深蹲',
      int sets = 3,
      int? reps = 12,
      int? durationSec,
    }) {
      return WorkoutTemplateItemEntity(
        id: 1,
        templateId: 1,
        exerciseId: exerciseId,
        exerciseName: name,
        category: 'strength',
        targetSets: sets,
        targetReps: reps,
        targetDurationSec: durationSec,
      );
    }

    test('模板动作 → 草稿条目：组数/次数沿用模板，重量留空', () {
      final entry = WorkoutLogEntry.fromTemplateItem(item());
      expect(entry.sets, 3);
      expect(entry.reps, 12);
      expect(entry.isTimed, isFalse);
      expect(entry.weightKg, isNull);
    });

    test('计时动作：带出秒数、不带次数', () {
      final entry =
          WorkoutLogEntry.fromTemplateItem(item(reps: null, durationSec: 60));
      expect(entry.isTimed, isTrue);
      expect(entry.durationSec, 60);
      expect(entry.reps, isNull);
    });

    test('组数 0 的脏数据兜底成 1（0 组等于没做）', () {
      final entry = WorkoutLogEntry.fromTemplateItem(item(sets: 0));
      expect(entry.sets, 1);
      expect(entry.toSets(), hasLength(1));
    });

    test('toSets：setNumber 从 1 递增，重量 0 落 null', () {
      const entry = WorkoutLogEntry(
        exerciseId: 7,
        exerciseName: '深蹲',
        category: 'strength',
        sets: 4,
        reps: 10,
        weightKg: 0,
      );
      final sets = entry.toSets();
      expect(sets.map((s) => s.setNumber).toList(), [1, 2, 3, 4]);
      expect(sets.every((s) => s.exerciseId == 7), isTrue);
      expect(sets.every((s) => s.reps == 10), isTrue);
      expect(sets.every((s) => s.weightKg == null), isTrue);
      expect(sets.every((s) => !s.isWarmup), isTrue);
    });

    test('重量 > 0 时逐组都带上', () {
      const entry = WorkoutLogEntry(
        exerciseId: 1,
        exerciseName: '卧推',
        category: 'strength',
        sets: 2,
        reps: 8,
        weightKg: 42.5,
      );
      expect(entry.toSets().map((s) => s.weightKg).toList(), [42.5, 42.5]);
    });

    test('同一动作不许加两次', () {
      var draft = const WorkoutLogDraft();
      draft = draft.add(WorkoutLogEntry.fromTemplateItem(item()));
      expect(draft.contains(1), isTrue);
      expect(draft.contains(2), isFalse);
    });

    test('删动作 / 改动作 / 合计组数', () {
      var draft = WorkoutLogDraft.fromTemplate(WorkoutTemplateEntity(
        id: 1,
        name: 't',
        difficulty: '入门',
        focus: '',
        minutes: 10,
        items: [item(), item(exerciseId: 2, name: '卧推', sets: 2)],
      ));
      expect(draft.totalSets, 5);

      draft = draft.replaceAt(1, draft.entries[1].copyWith(sets: 5));
      expect(draft.totalSets, 8);

      draft = draft.removeAt(0);
      expect(draft.entries.single.exerciseName, '卧推');
      expect(draft.totalSets, 5);
    });

    test('空白草稿不能保存；越界删改不崩', () {
      const draft = WorkoutLogDraft();
      expect(draft.isEmpty, isTrue);
      expect(draft.canSave, isFalse);
      expect(draft.removeAt(0).isEmpty, isTrue);
      expect(
          draft
              .replaceAt(3,
                  const WorkoutLogEntry(exerciseId: 1, exerciseName: 'x', category: 'strength', sets: 1))
              .isEmpty,
          isTrue);
      expect(draft.toSets(), isEmpty);
    });
  });
}
