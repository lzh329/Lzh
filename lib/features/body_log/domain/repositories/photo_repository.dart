import 'dart:io';
import 'package:fittrack/core/database/database.dart';

abstract class PhotoRepository {
  Future<List<Photo>> getAll({DateTime? from, DateTime? to});
  Future<Photo> addPhoto({required DateTime date, required File imageFile, String? note});
  Future<void> delete(int id);
}
