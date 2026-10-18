import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/database/database.dart';

const _red = Color(0xFFEF5350);

/// 删除确认弹窗；返回 true 表示确认删除
Future<bool> confirmDeletePhoto(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除照片'),
      content: const Text('删除后无法恢复，确定要删除这张照片吗？'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('删除', style: TextStyle(color: _red)),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 全屏预览一张身体照片
///
/// 返回 `true` 表示用户确认「删除这张照片」，调用方负责删库删文件并刷新；
/// 返回 `null` / `false` 表示只是看了看。
Future<bool?> showPhotoPreview(BuildContext context, Photo photo) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final top = MediaQuery.of(dialogContext).padding.top + 8;
      // 拍照/记录体重时可能填了备注，有则浮在底部
      final note = (photo.note ?? '').trim();

      Widget roundButton(IconData icon, Color color, VoidCallback onTap) =>
          IconButton(
            onPressed: onTap,
            icon: Icon(icon, color: color, size: 22),
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
          );

      Future<void> requestDelete() async {
        final ok = await confirmDeletePhoto(dialogContext);
        if (ok && dialogContext.mounted) {
          Navigator.of(dialogContext).pop(true);
        }
      }

      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Center(
                  child: Icon(Icons.broken_image,
                      size: 48, color: Colors.white24),
                ),
              ),
            ),
            Positioned(
              top: top,
              left: 8,
              child: roundButton(Icons.close, Colors.white,
                  () => Navigator.of(dialogContext).pop()),
            ),
            Positioned(
              top: top,
              right: 8,
              child: roundButton(Icons.delete_outline, _red, requestDelete),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (note.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(note,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                  Text(DateFormat('yyyy年M月d日').format(photo.date),
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
