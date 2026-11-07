import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/theme/app_colors.dart';

import 'album_action_sheets.dart';

/// 对比页「换一张」选择器：列出全部照片，返回用户选中的那张
///
/// 为什么不做成日期选择器：用户是按"哪张照片"记忆的（穿什么、光线），
/// 而不是按日期。列表里同时给日期、分类与当天体重，足够定位。
Future<Photo?> showComparePhotoPicker(
  BuildContext context, {
  required List<Photo> photos,
  required String title,
  int? currentId,
  Map<String, double> weights = const {},
}) {
  return showModalBottomSheet<Photo>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('按日期或体型挑选，选中后立即替换',
                  style: TextStyle(
                      fontSize: 11.5, color: AppColors.textTertiary)),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: photos.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 76),
                itemBuilder: (_, i) {
                  final photo = photos[i];
                  final date = DateFormat('yyyy年M月d日').format(photo.date);
                  final category =
                      photo.category == null ? null : PhotoCategories.label(photo.category);
                  final kg = _weightOf(photo, weights);
                  return ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photo.filePath),
                        width: 48,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 48,
                          height: 60,
                          color: AppColors.surfaceAlt,
                          child: const Icon(Icons.broken_image, size: 16),
                        ),
                      ),
                    ),
                    title: Text(date, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                      [
                        if (category != null) category,
                        if (kg != null) '${(kg * 2).toStringAsFixed(1)} 斤',
                        if (category == null && kg == null) '未记录体重',
                      ].join(' · '),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                    trailing: photo.id == currentId
                        ? const Icon(Icons.check,
                            size: 18, color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(ctx, photo),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

double? _weightOf(Photo photo, Map<String, double> weights) {
  final key = DateTime(photo.date.year, photo.date.month, photo.date.day)
      .toIso8601String();
  return weights[key];
}
