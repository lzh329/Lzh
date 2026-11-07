import 'dart:io';
import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PhotoRepositoryImpl implements PhotoRepository {
  final AppDatabase _db;

  /// 仅测试注入：指定照片目录，避免依赖 path_provider 平台通道
  final Directory? _photosDirOverride;

  PhotoRepositoryImpl(this._db, {Directory? photosDir})
      : _photosDirOverride = photosDir;

  @override
  Future<List<Photo>> getAll({DateTime? from, DateTime? to}) async {
    var query = _db.select(_db.photos)
      ..orderBy([(t) => OrderingTerm.desc(t.date)]);

    if (from != null) {
      query = query..where((t) => t.date.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      final nextDay = to.add(const Duration(days: 1));
      query = query..where((t) => t.date.isSmallerThanValue(nextDay));
    }

    return await query.get();
  }

  @override
  Future<Photo> addPhoto(
      {required DateTime date,
      required File imageFile,
      String? note,
      String? category}) async {
    final copied = await _copyIntoLibrary(date, imageFile);
    return _insert(date: date, filePath: copied, note: note, category: category);
  }

  @override
  Future<List<Photo>> addPhotos({
    required List<File> files,
    required DateTime date,
    String? category,
  }) async {
    final out = <Photo>[];
    for (final f in files) {
      try {
        final copied = await _copyIntoLibrary(date, f);
        out.add(await _insert(
            date: date, filePath: copied, note: null, category: category));
      } catch (_) {
        // 单张失败（文件损坏 / 无权限）不阻断其余：用户至少能拿到成功的那些
        continue;
      }
    }
    return out;
  }

  @override
  Future<void> updateCategory(int id, String? category) async {
    await (_db.update(_db.photos)..where((t) => t.id.equals(id)))
        .write(PhotosCompanion(category: Value(category)));
  }

  @override
  Future<void> delete(int id) async {
    final photo = await (_db.select(_db.photos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (photo != null) {
      await _deleteFile(photo.filePath);
    }
    await (_db.delete(_db.photos)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> deleteMany(List<int> ids) async {
    if (ids.isEmpty) return;
    final rows = await (_db.select(_db.photos)..where((t) => t.id.isIn(ids)))
        .get();
    for (final r in rows) {
      await _deleteFile(r.filePath);
    }
    await (_db.delete(_db.photos)..where((t) => t.id.isIn(ids))).go();
  }

  // ── 内部 ──

  /// 复制到应用内部存储；文件名带时间戳 + 序号，保证同批导入不重名
  Future<String> _copyIntoLibrary(DateTime date, File src) async {
    final Directory photosDir;
    if (_photosDirOverride != null) {
      photosDir = _photosDirOverride;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      photosDir = Directory(p.join(appDir.path, 'photos'));
    }
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }
    final ext = p.extension(src.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    // 文件名必须跨平台安全：Windows 不允许冒号（`2026-11-07T10:00:00` 会写失败）
    final day = date.toIso8601String().split('T').first;
    final destPath = p.join(photosDir.path, '${day}_$stamp$ext');
    await src.copy(destPath);
    return destPath;
  }

  Future<Photo> _insert({
    required DateTime date,
    required String filePath,
    String? note,
    String? category,
  }) async {
    final id = await _db.into(_db.photos).insert(PhotosCompanion.insert(
          date: date,
          filePath: filePath,
          note: Value(note),
          category: Value(category),
        ));
    return Photo(
      id: id,
      date: date,
      filePath: filePath,
      note: note,
      category: category,
    );
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 文件删不掉不影响行删除（否则会留下"点了没反应"的幽灵记录）
    }
  }
}
