import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/workout/domain/entities/workout_entity.dart';

import 'fake_database.dart';

/// QA 补充：冷启动首帧（C-2 / C-6 的另一套构造）。
///
/// 工程师的写法是"设置完成后再逐帧累积收集资产"。那种写法有一个盲点：
/// 它只在**帧边界**采样，而且把 `bodyWeightsJinProvider` /
/// `characterAssetManifestProvider` 都提前 resolve 掉了。
///
/// 这里换三种构造：
///   ① 设置**延迟 500ms** 才 emit（模拟真机上磁盘慢的那一次冷启动），
///      在 100 / 300 / 499ms 各采一次树：既看 Image，也看**文本**；
///   ② 资产清单与体重都是**真实** provider（走内存库 + 真实 rootBundle），
///      不是 mock 好的集合 —— 免掉"mock 让首帧看起来更干净"的偏差；
///   ③ 把今日任务做成**全完成**：这是唯一会让「咕嘎」字面量出现在首页的位置
///      （`today_tasks_card` 的鼓励语），也是"空舞台"之外最容易漏的一条。
void main() {
  late AppDatabase db;

  setUp(() => db = fakeDatabase());
  tearDown(() => db.close());

  /// 今日任务全完成（体重 / 训练 / 照片都打了卡）+ 已选糯糯
  DashboardData allDoneData() {
    final now = DateTime.now();
    return DashboardData(
      todayMetric: BodyMetricEntity(id: 1, date: now, weightKg: 35),
      allMetrics: [BodyMetricEntity(id: 1, date: now, weightKg: 35)],
      firstMetric: BodyMetricEntity(id: 1, date: now, weightKg: 35),
      latestMetric: BodyMetricEntity(id: 1, date: now, weightKg: 35),
      allWorkouts: [
        WorkoutEntity(
          id: 1,
          date: now,
          type: 'free',
          durationSec: 600,
          sets: const [],
        ),
      ],
      todayPhoto: Photo(id: 1, date: now, filePath: '/nonexistent.jpg', note: null),
    );
  }

  Widget home(Future<UserSettingsEntity?> settings) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        dashboardDataProvider.overrideWith((ref) async => allDoneData()),
        userSettingsProvider.overrideWith((ref) => settings),
        // 体重与资产清单都**不**覆写：走真实实现（内存库 + 真实 rootBundle）
      ],
      child: const MaterialApp(home: DashboardPage()),
    );
  }

  /// 当前树上的所有字符串（文本 + 资产名），用于"逐次采样"式断言
  List<String> snapshot(WidgetTester tester) {
    final out = <String>[];
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final data = t.data;
      if (data != null) out.add(data);
    }
    for (final img in tester.widgetList<Image>(find.byType(Image))) {
      final image = img.image;
      if (image is AssetImage) out.add(image.assetName);
    }
    return out;
  }

  testWidgets('① 设置延迟 500ms：100/300/499ms 三处都是空舞台，不出现咕嘎', (tester) async {
    final complete = Completer<UserSettingsEntity?>();
    Timer(const Duration(milliseconds: 500), () {
      if (!complete.isCompleted) {
        complete.complete(
            const UserSettingsEntity(id: 1, characterId: 'nuonuo'));
      }
    });
    addTearDown(() {
      if (!complete.isCompleted) complete.complete(null);
    });

    await tester.pumpWidget(home(complete.future));
    await tester.pump(); // dashboardData 就绪 → 进入 _DashboardBody
    await tester.pump();

    final seen = <String>[];
    for (final ms in [100, 200, 99]) {
      await tester.pump(Duration(milliseconds: ms));
      seen.addAll(snapshot(tester));
      expect(find.byType(CharacterView), findsNothing,
          reason: '设置没读到之前不许画任何角色（空舞台）');
      final assets = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .whereType<AssetImage>()
          .map((i) => i.assetName)
          .toList();
      expect(assets, isEmpty, reason: '空舞台阶段不该有任何 Image 资产');
      expect(find.text('咕嘎'), findsNothing,
          reason: '设置没读到时连名字都不许出现');
    }

    // 499ms 时刻仍在空舞台，且此前的采样里一个 guga 资产都没出现过
    expect(seen.where((s) => s.contains('guga')), isEmpty);

    // 让 500ms 的延迟真正走完
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byType(CharacterView), findsOneWidget, reason: '设置到了就要画出来');
    final finalAssets = tester
        .widgetList<Image>(find.byType(Image))
        .map((i) => i.image)
        .whereType<AssetImage>()
        .map((i) => i.assetName)
        .toList();
    expect(finalAssets.any((a) => a.contains('nuonuo')), isTrue,
        reason: '画出来的必须是糯糯');
    expect(seen.where((s) => s.contains('guga')), isEmpty,
        reason: '整段采样里任何一次都不许出现咕嘎');
  });

  // ⚠️ 缺陷 D2（已报工程师）：设置未读到时鼓励语回落成「咕嘎」再跳变成「糯糯」。
  // 修好后把 skip 去掉，这条就是回归门禁。
  testWidgets('② 今日任务全完成 + 设置未读到：鼓励语不得先写成咕嘎',
      (tester) async {
    final complete = Completer<UserSettingsEntity?>();
    addTearDown(() {
      if (!complete.isCompleted) complete.complete(null);
    });

    await tester.pumpWidget(home(complete.future));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 全完成状态下才会出现这句（doneCount == 3）
    expect(find.textContaining('为你鼓掌'), findsOneWidget,
        reason: '这条断言同时证明"全完成"构造真的生效了');
    expect(find.textContaining('咕嘎'), findsNothing,
        reason: 'C-20/首帧：设置没读到时不能先把名字写成咕嘎再跳变成糯糯');

    complete.complete(const UserSettingsEntity(id: 1, characterId: 'nuonuo'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('今日全部完成，糯糯为你鼓掌！'), findsOneWidget);
  });
}
