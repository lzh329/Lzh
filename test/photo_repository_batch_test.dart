import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fittrack/features/body_log/data/photo_repository_impl.dart';

import 'fake_database.dart';

/// 照片仓储的批量能力：批量入库 / 改分类 / 批量删除（含文件）
void main() {
  late Directory tmp;
  late Directory photosDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('fittrack_photos');
    photosDir = Directory(p.join(tmp.path, 'photos'));
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  /// 造一张"源文件"（内容不重要，复制行为才重要）
  File srcFile(String name) {
    final f = File(p.join(tmp.path, name))
      ..writeAsStringSync('img:$name');
    return f;
  }

  test('addPhotos：N 张全部入库、路径互不重复、同批不覆盖', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = PhotoRepositoryImpl(db, photosDir: photosDir);

    final files = [srcFile('a.jpg'), srcFile('b.jpg'), srcFile('c.jpg')];
    final added = await repo.addPhotos(
      files: files,
      date: DateTime(2026, 11, 7),
      category: 'side',
    );

    expect(added, hasLength(3));
    final paths = added.map((e) => e.filePath).toSet();
    expect(paths, hasLength(3), reason: '同批导入不能互相覆盖');
    for (final photo in added) {
      expect(File(photo.filePath).existsSync(), isTrue);
      expect(photo.category, 'side');
    }

    final all = await repo.getAll();
    expect(all, hasLength(3));
  });

  test('addPhotos：跳过分类时 category 为 null', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = PhotoRepositoryImpl(db, photosDir: photosDir);

    final added = await repo.addPhotos(
      files: [srcFile('a.jpg')],
      date: DateTime(2026, 11, 7),
    );
    expect(added.single.category, isNull);

    final all = await repo.getAll();
    expect(all.single.category, isNull);
  });

  test('updateCategory：改分类与清空都落库', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = PhotoRepositoryImpl(db, photosDir: photosDir);

    final photo = await repo.addPhoto(
        date: DateTime(2026, 11, 7), imageFile: srcFile('a.jpg'));
    await repo.updateCategory(photo.id, 'front');
    expect((await repo.getAll()).single.category, 'front');

    await repo.updateCategory(photo.id, null);
    expect((await repo.getAll()).single.category, isNull);
  });

  test('deleteMany：行与文件同时删掉，其余照片不受影响', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = PhotoRepositoryImpl(db, photosDir: photosDir);

    final added = await repo.addPhotos(
      files: [srcFile('a.jpg'), srcFile('b.jpg'), srcFile('c.jpg')],
      date: DateTime(2026, 11, 7),
    );
    final victims = added.take(2).toList();
    final survivor = added.last;

    await repo.deleteMany(victims.map((e) => e.id).toList());

    final rest = await repo.getAll();
    expect(rest, hasLength(1));
    expect(rest.single.id, survivor.id);
    for (final v in victims) {
      expect(File(v.filePath).existsSync(), isFalse, reason: '文件必须一起删');
    }
    expect(File(survivor.filePath).existsSync(), isTrue);
  });

  test('deleteMany：空列表是 no-op', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = PhotoRepositoryImpl(db, photosDir: photosDir);
    await repo.addPhoto(
        date: DateTime(2026, 11, 7), imageFile: srcFile('a.jpg'));

    await repo.deleteMany(const []);
    expect(await repo.getAll(), hasLength(1));
  });
}
