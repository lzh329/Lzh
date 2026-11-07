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
import 'package:fittrack/features/body_log/presentation/pages/body_album_page.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_tile.dart';

/// 身体相册：批量选择删除 / 分类标签 / 长按改分类
void main() {
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    tmp = await Directory.systemTemp.createTemp('fittrack_album_test');
  });

  tearDown(() async {
    await db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  File seedFile(String name) =>
      File(p.join(tmp.path, name))..writeAsStringSync('img');

  Future<int> seedPhoto({String category = ''}) {
    return db.into(db.photos).insert(PhotosCompanion.insert(
          date: DateTime(2026, 11, 7),
          filePath:
              seedFile('${DateTime.now().microsecondsSinceEpoch}.jpg').path,
          category: Value(category.isEmpty ? null : category),
        ));
  }

  Future<void> pumpAlbum(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const BodyAlbumPage()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('批量选择 2 张并删除，其余保留', (tester) async {
    await seedPhoto();
    await seedPhoto();
    await seedPhoto();
    await pumpAlbum(tester);

    await tester.tap(find.byTooltip('批量选择'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 张'), findsOneWidget);

    await tester.tap(find.byType(PhotoTile).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PhotoTile).at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 张'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 张照片？'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除')));
    await tester.pumpAndSettle();

    final left = await db.select(db.photos).get();
    expect(left, hasLength(1), reason: '只删选中的两张');
  });

  testWidgets('分类标签渲染：已分类的照片显示角度文字', (tester) async {
    await seedPhoto(category: 'side');
    await pumpAlbum(tester);

    expect(find.text('侧面'), findsOneWidget);
  });

  testWidgets('长按 → 设为正面：落库并显示标签', (tester) async {
    final id = await seedPhoto();
    await pumpAlbum(tester);

    await tester.longPress(find.byType(PhotoTile).first);
    await tester.pumpAndSettle();
    expect(find.text('这张照片'), findsOneWidget);

    await tester.tap(find.text('设为正面'));
    await tester.pumpAndSettle();

    final row =
        await (db.select(db.photos)..where((t) => t.id.equals(id))).getSingle();
    expect(row.category, 'front');
    expect(find.text('正面'), findsOneWidget);
  });
}
