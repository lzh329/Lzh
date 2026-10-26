import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_compare_page.dart'
    show photoDayKey;

/// 身体对比页（全屏并排）—— 最早 vs 最新，图片铺满半屏
class BodyComparePage extends ConsumerStatefulWidget {
  const BodyComparePage({super.key});

  @override
  ConsumerState<BodyComparePage> createState() => _BodyComparePageState();
}

class _BodyComparePageState extends ConsumerState<BodyComparePage> {
  List<Photo> _photos = const [];
  Map<String, double> _weights = const {};
  bool _loading = true;

  static const _orange = AppColors.primary;
  static const _green = AppColors.success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final photos = await ref.read(photoRepoProvider).getAll();
      final metrics = await ref.read(bodyMetricRepoProvider).getAll();
      final sorted = List<Photo>.from(photos)
        ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _photos = sorted;
        _weights = {for (final m in metrics) photoDayKey(m.date): m.weightKg};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double? _weightJin(Photo p) {
    final kg = _weights[photoDayKey(p.date)];
    return kg == null ? null : kg * 2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_photos.length < 2) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('身体对比'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.compare,
                  size: 48, color: AppColors.borderStrong),
              const SizedBox(height: 14),
              Text('至少需要两张照片才能对比', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(
                '去「身体相册」拍一张，和最早的照片对比',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      );
    }

    final latest = _photos.first;
    final earliest = _photos.last;
    final leftJin = _weightJin(earliest);
    final rightJin = _weightJin(latest);
    final days = latest.date.difference(earliest.date).inDays.abs();
    final diffJin =
        (leftJin != null && rightJin != null) ? leftJin - rightJin : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('身体对比'),
        actions: [
          IconButton(
            tooltip: '去相册',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 左右全屏并排 ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _panel(context, earliest, '最早', leftJin),
                  Container(width: 2, color: AppColors.background),
                  _panel(context, latest, '最新', rightJin),
                ],
              ),
            ),
            // ── 底部数据条 ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '时间跨度',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$days 天',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (diffJin != null) ...[
                    Container(
                      width: 1,
                      height: 36,
                      color: AppColors.border,
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '体重变化',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${diffJin > 0 ? '-' : '+'}${diffJin.abs().toStringAsFixed(1)}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.1,
                                  color: diffJin > 0
                                      ? _green
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Text(
                                '斤',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单侧照片（铺满、角标、底部渐变信息、点击放大）
  Widget _panel(BuildContext context, Photo photo, String label, double? jin) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _preview(context, photo),
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
                    color: label == '最新' ? _orange : Colors.black54,
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
                          '${jin.toStringAsFixed(1)} 斤',
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

  /// 全屏预览（可双指缩放）
  void _preview(BuildContext context, Photo photo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.file(
                File(photo.filePath),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
