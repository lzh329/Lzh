import 'dart:io';
import 'package:fittrack/core/database/database.dart';

/// 身体照片仓储。
///
/// 分类口径：`category` 取值 `front` / `side` / `back`，`null` = 未分类
/// （产品上允许"跳过分类"，所以不设默认值、不做非空约束）。
abstract class PhotoRepository {
  Future<List<Photo>> getAll({DateTime? from, DateTime? to});

  Future<Photo> addPhoto(
      {required DateTime date,
      required File imageFile,
      String? note,
      String? category});

  /// 批量导入（相册多选 / 连续拍摄）：逐张复制入库，单张失败不阻断其余
  Future<List<Photo>> addPhotos({
    required List<File> files,
    required DateTime date,
    String? category,
  });

  /// 改分类；传 null = 清空为未分类
  Future<void> updateCategory(int id, String? category);

  Future<void> delete(int id);

  /// 批量删除（先删文件再删行；单条失败不阻断其余）
  Future<void> deleteMany(List<int> ids);
}
