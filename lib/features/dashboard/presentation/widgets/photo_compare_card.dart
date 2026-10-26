import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 首页「身体变化对比」卡 —— 最早 vs 最新照片 + 累计减重
class PhotoCompareCard extends StatelessWidget {
  final String? firstPath;
  final DateTime? firstDate;
  final String? latestPath;
  final DateTime? latestDate;
  final double? lossJin;
  final VoidCallback onTap;

  const PhotoCompareCard({
    super.key,
    this.firstPath,
    this.firstDate,
    this.latestPath,
    this.latestDate,
    this.lossJin,
    required this.onTap,
  });

  static const _orange = AppColors.primary;
  static const _green = AppColors.success;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasBoth = firstPath != null && latestPath != null;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('身体变化对比', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (lossJin != null && lossJin! > 0)
                    Text(
                      '已减 ${lossJin!.toStringAsFixed(1)} 斤',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _green),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _slot(theme,
                        path: firstPath, date: firstDate, label: '最早'),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.compare_arrows, size: 18, color: _orange),
                  ),
                  Expanded(
                    child: _slot(theme,
                        path: latestPath,
                        date: latestDate,
                        label: '最新',
                        highlight: true),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 52,
                      height: 64,
                      decoration: BoxDecoration(
                        color: _orange.withAlpha(26),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: _orange.withAlpha(70), width: 0.8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.compare, size: 16, color: _orange),
                          const SizedBox(height: 2),
                          Text(
                            hasBoth ? '看对比' : '去添加',
                            style: const TextStyle(
                                fontSize: 9,
                                color: _orange,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slot(
    ThemeData theme, {
    required String? path,
    required DateTime? date,
    required String label,
    bool highlight = false,
  }) {
    return Container(
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: highlight
            ? Border.all(color: _orange.withAlpha(80), width: 0.8)
            : null,
      ),
      child: path == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo_outlined,
                      size: 16, color: AppColors.textTertiary),
                  const SizedBox(height: 2),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textTertiary)),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black.withAlpha(120),
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      date != null
                          ? '${DateFormat('M/d').format(date)} · $label'
                          : label,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(fontSize: 8.5, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
