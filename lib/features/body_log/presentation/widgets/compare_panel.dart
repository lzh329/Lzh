import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 对比页单侧照片面板（铺满 + 角标 + 底部渐变信息 + 点击放大）
///
/// 从 body_compare_page 原样搬出，只把私有方法改成公开 widget。
class ComparePhotoPanel extends StatelessWidget {
  final Photo photo;
  final String label;
  final double? jin;
  final VoidCallback onTap;

  /// 「换一张」：传 null 不显示按钮
  final VoidCallback? onChange;

  const ComparePhotoPanel({
    super.key,
    required this.photo,
    required this.label,
    required this.jin,
    required this.onTap,
    this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 背景：原图铺满并压暗（只做氛围，不承担"看人"的职责）
              Image.file(
                File(photo.filePath),
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                opacity: const AlwaysStoppedAnimation(0.26),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
              // 前景：完整人像（contain 不裁切 + 高质量滤波）
              Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.broken_image,
                      size: 36, color: Colors.white.withAlpha(60)),
                ),
              ),
              // 顶部标签
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: label == '最新' ? AppColors.primary : Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: label == '最新' ? Colors.black : Colors.white70,
                    ),
                  ),
                ),
              ),
              // 右上角「换一张」
              if (onChange != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black.withAlpha(130),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onChange,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 13, color: Colors.white),
                            SizedBox(width: 3),
                            Text('换一张',
                                style: TextStyle(
                                    fontSize: 10.5, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // 底部渐变 + 日期 / 体重
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 28, 10, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withAlpha(210),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('yyyy.MM.dd').format(photo.date),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.white.withAlpha(200),
                        ),
                      ),
                      if (jin != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${jin!.toStringAsFixed(1)} 斤',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
