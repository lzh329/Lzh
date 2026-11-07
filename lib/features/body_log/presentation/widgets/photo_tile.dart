import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/theme/app_colors.dart';

const _green = AppColors.primary;

/// 相册单格：圆角封面 + 底部日期半透明条
///
/// [selecting] 为 true 时（对比选择态）右上角显示勾选圈；
/// [order] 为已选序号（1 / 2），选中格显示序号徽标并加绿色描边。
class PhotoTile extends StatelessWidget {
  final Photo photo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final int? order;

  /// 多选模式下的「已勾选」标记（与对比的 1/2 序号区分）
  final bool checked;

  /// 分类标签（正面/侧面/背面）；null 不显示
  final String? categoryLabel;

  const PhotoTile({
    super.key,
    required this.photo,
    required this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.order,
    this.checked = false,
    this.categoryLabel,
  });

  @override
  Widget build(BuildContext context) {
    // 多选态用 checked（没有序号），对比态用 order；两者都算"已选中"
    final selected = order != null || checked;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(photo.filePath),
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(
                color: AppColors.surfaceAlt,
                child: const Icon(Icons.broken_image,
                    size: 20, color: AppColors.textTertiary),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withAlpha(120),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(DateFormat('M/d').format(photo.date),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9.5)),
              ),
            ),
            if (categoryLabel != null && !selecting)
              Positioned(
                left: 4,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(140),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(categoryLabel!,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            if (selecting)
              Positioned(
                top: 4,
                right: 4,
                child: selected
                    ? Container(
                        width: 18,
                        height: 18,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: _green,
                          shape: BoxShape.circle,
                        ),
                        child: checked
                            ? const Icon(Icons.check,
                                size: 12, color: AppColors.onPrimary)
                            : Text('$order',
                                style: const TextStyle(
                                    color: AppColors.onPrimary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                      )
                    : const Icon(Icons.radio_button_unchecked,
                        size: 18, color: Colors.white70),
              ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: _green, width: 2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
