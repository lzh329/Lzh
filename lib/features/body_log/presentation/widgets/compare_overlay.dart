import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/database/database.dart';

/// 叠加滑动对比：左侧旧照覆盖在右侧新照之上，中间可拖动分割线
///
/// 为什么用 ClipRect + Align 而不是 Stack 里叠两张 Positioned：
/// 分割线拖动时只需要重建裁剪宽度，图片解码结果复用，拖动才跟手。
class CompareOverlay extends StatelessWidget {
  final Photo before;
  final Photo after;
  final double split; // 0..1
  final ValueChanged<double> onSplitChanged;
  final String beforeLabel;
  final String afterLabel;

  const CompareOverlay({
    super.key,
    required this.before,
    required this.after,
    required this.split,
    required this.onSplitChanged,
    required this.beforeLabel,
    required this.afterLabel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final dx = d.localPosition.dx / box.size.width;
        onSplitChanged(dx.clamp(0.02, 0.98));
      },
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        onSplitChanged((d.localPosition.dx / box.size.width).clamp(0.02, 0.98));
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _photo(after),
            // 旧照按分割线裁剪（左半）
            ClipRect(
              clipper: _LeftClipper(split),
              child: _photo(before),
            ),
            // 分割线 + 手柄
            Positioned(
              left: MediaQuery.sizeOf(context).width * split - 1,
              top: 0,
              bottom: 0,
              child: Container(width: 2, color: Colors.white.withAlpha(220)),
            ),
            Positioned(
              left: MediaQuery.sizeOf(context).width * split - 18,
              top: MediaQuery.sizeOf(context).height * 0.45,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(60), blurRadius: 8)
                  ],
                ),
                child: const Icon(Icons.drag_handle,
                    size: 18, color: Colors.black87),
              ),
            ),
            // 角标
            Positioned(
              left: 10,
              bottom: 10,
              child: _badge(beforeLabel),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: _badge(afterLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photo(Photo p) => Image.file(
        File(p.filePath),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 36, color: Colors.white24),
        ),
      );

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(140),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 10.5)),
      );
}

/// 左侧裁剪（按比例保留左半部分）
class _LeftClipper extends CustomClipper<Rect> {
  final double split;
  const _LeftClipper(this.split);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftClipper oldClipper) => oldClipper.split != split;
}

/// 日期标签：有体重时追加斤数（与全 App 展示口径一致）
String compareDateLabel(Photo photo, double? jin) {
  final d = DateFormat('M月d日').format(photo.date);
  return jin == null ? d : '$d · ${jin.toStringAsFixed(1)}斤';
}
