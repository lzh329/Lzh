import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 照片按天归一的 key，用于关联同一天的体重记录
String photoDayKey(DateTime date) =>
    DateTime(date.year, date.month, date.day).toIso8601String();

/// 前后对比页：左右并排两张照片，各占一半宽，中间竖线分隔
///
/// 每张照片下方标注「标签 + 日期（+ 当天体重，若有）」，
/// 底部显示两张照片相差的天数。
class PhotoComparePage extends StatelessWidget {
  final Photo before;
  final Photo after;

  /// 日期 key（见 [photoDayKey]）→ 体重，单位 kg（数据库存储单位）
  final Map<String, double> weights;

  const PhotoComparePage({
    super.key,
    required this.before,
    required this.after,
    this.weights = const {},
  });

  /// 标注文字：日期，若当天有体重记录则追加斤数
  ///
  /// 注意：库里存 kg，而全 App 的体重展示单位是「斤」（1 斤 = 0.5 kg），
  /// 故这里与体重页保持一致，展示 `kg × 2` 的斤数。
  String _caption(Photo photo) {
    final date = DateFormat('M月d日').format(photo.date);
    final kg = weights[photoDayKey(photo.date)];
    return kg == null ? date : '$date · ${(kg * 2).toStringAsFixed(1)}斤';
  }

  Widget _side(Photo photo, String label) {
    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.file(
                  File(photo.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(Icons.broken_image,
                        size: 40, color: Colors.white24),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                Text(_caption(photo),
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = before.date.difference(after.date).inDays.abs();

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('照片对比'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _side(before, '之前'),
                  Container(width: 1, color: AppColors.border),
                  _side(after, '之后'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text('$days 天的变化',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }
}
