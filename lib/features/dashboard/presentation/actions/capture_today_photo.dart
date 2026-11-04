import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fittrack/core/providers.dart';

/// 首页「今日图片」：拍照 → 存为身体照片 → 刷新首页。
///
/// 为什么单独成文件：这是**动作**不是排版（要弹系统相机、要写库、要刷新），
/// 埋在页面里既顶行数又让"首页只负责画"这条约定失效。
Future<void> captureTodayPhoto(BuildContext context, WidgetRef ref) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: ImageSource.camera,
    maxWidth: 2000,
    imageQuality: 92,
  );
  // 用户取消拍照：什么都不做（不能弹"失败"——他本来就没想记）
  if (file == null) return;

  await ref.read(photoRepoProvider).addPhoto(
        date: DateTime.now(),
        imageFile: File(file.path),
      );
  ref.invalidate(dashboardDataProvider);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('今日图片已记录')),
    );
  }
}
