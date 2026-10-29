import 'dart:io';

import 'package:image_picker/image_picker.dart';

import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';

/// 从相册导入一张对比照的结果
enum PhotoImportOutcome {
  /// 已写入照片库
  imported,

  /// 用户在选图界面取消（静默返回，不提示）
  cancelled,

  /// 选图或写库失败（原因给用户看）
  failed,
}

class PhotoImportResult {
  final PhotoImportOutcome outcome;
  final String? error;

  const PhotoImportResult(this.outcome, {this.error});
}

/// 选中文件的入库参数（**纯函数**，便于单测）
///
/// 日期取"今天"：用户从相册导入的往往是旧照片，但我们没有 EXIF 读取通道，
/// 与其猜一个日期，不如按导入日算并让用户在相册里改。
({DateTime date, File imageFile, String note}) buildPhotoImportArgs(
  File picked, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  return (
    date: DateTime(at.year, at.month, at.day),
    imageFile: picked,
    // note 写清来源，避免以后分不清"今天拍的"和"从相册翻出来的旧照"
    note: '相册导入',
  );
}

/// 从相册选一张图并写入照片库
///
/// 文件拷贝交给仓储（`addPhoto` 内部会复制到 documents/photos），
/// 这里**不自己 copy** —— 否则会出现"库里有记录但文件在别处"的孤儿。
Future<PhotoImportResult> importPhotoFromGallery({
  required PhotoRepository repo,
  ImagePicker? picker,
  DateTime? now,
}) async {
  try {
    final picked = await (picker ?? ImagePicker()).pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 92,
    );
    if (picked == null) {
      return const PhotoImportResult(PhotoImportOutcome.cancelled);
    }
    final args = buildPhotoImportArgs(File(picked.path), now: now);
    await repo.addPhoto(
      date: args.date,
      imageFile: args.imageFile,
      note: args.note,
    );
    return const PhotoImportResult(PhotoImportOutcome.imported);
  } catch (e) {
    return PhotoImportResult(
      PhotoImportOutcome.failed,
      error: e.toString(),
    );
  }
}
