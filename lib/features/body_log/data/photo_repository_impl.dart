import 'dart:io';
import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class PhotoRepositoryImpl implements PhotoRepository {
  final AppDatabase _db;
  PhotoRepositoryImpl(this._db);

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
      {required DateTime date, required File imageFile, String? note}) async {
    // 复制到应用内部存储
    final appDir = await getApplicationDocumentsDirectory();
    final photosDir = Directory(p.join(appDir.path, 'photos'));
    if (!await photosDir.exists()) {
      await photosDir.create(recursive: true);
    }

    final ext = p.extension(imageFile.path);
    final fileName =
        '${date.toIso8601String()}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final destPath = p.join(photosDir.path, fileName);
    await imageFile.copy(destPath);

    final id = await _db.into(_db.photos).insert(PhotosCompanion.insert(
          date: date,
          filePath: destPath,
          note: Value(note),
        ));

    return Photo(
      id: id,
      date: date,
      filePath: destPath,
      note: note,
    );
  }

  @override
  Future<void> delete(int id) async {
    final photo = await (_db.select(_db.photos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (photo != null) {
      final file = File(photo.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await (_db.delete(_db.photos)..where((t) => t.id.equals(id))).go();
  }
}
