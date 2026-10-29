import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_empty_state.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_import.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_panel.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_review_launcher.dart';
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

  /// 截屏用的 key（只包并排对比区域，不把按钮和底栏截进去）
  final GlobalKey _captureKey = GlobalKey();

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

  /// 从相册导入一张对比照（走 photoRepo.addPhoto，文件拷贝由仓储负责）
  Future<void> _importFromGallery() async {
    final result = await importPhotoFromGallery(
      repo: ref.read(photoRepoProvider),
    );
    if (!mounted) return;
    switch (result.outcome) {
      case PhotoImportOutcome.imported:
        await _load();
        if (!mounted) return;
        _toast('已导入，可在对比里查看');
      case PhotoImportOutcome.cancelled:
        return; // 用户取消：静默，不弹任何提示
      case PhotoImportOutcome.failed:
        // 相册权限被拒是最常见原因，给可操作提示而不是干巴巴的"失败了"
        final denied = '${result.error}'.toLowerCase().contains('permission');
        _toast(denied
            ? '没有相册权限，去系统设置里允许「照片」后重试'
            : '导入失败：${result.error ?? '未知原因'}');
    }
  }

  /// 把并排对比画面截成一张图，带去嘎教练页让 AI 点评
  Future<void> _askCoachToReview() async {
    final png = await captureBoundaryPng(_captureKey);
    if (png == null) {
      _toast('截图失败，先自己看看两张照片吧');
      return;
    }
    final file = await writeCompareSnapshot(png);
    if (!mounted) return;
    context.push('/ai/coach', extra: {
      'imagePath': file.path,
      'text': compareReviewPrompt,
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_photos.length < 2) {
      return CompareEmptyState(onImport: _importFromGallery);
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
            tooltip: '从相册导入',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _importFromGallery,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 左右全屏并排 ──
            Expanded(
              // RepaintBoundary 包住"用户看到的这块画面"：
              // DeepSeek 视觉一次只吃一张图，所以截整块而不是分两次发两张
              child: RepaintBoundary(
                key: _captureKey,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ComparePhotoPanel(
                      photo: earliest,
                      label: '最早',
                      jin: leftJin,
                      onTap: () => _preview(context, earliest),
                    ),
                    Container(width: 2, color: AppColors.background),
                    ComparePhotoPanel(
                      photo: latest,
                      label: '最新',
                      jin: rightJin,
                      onTap: () => _preview(context, latest),
                    ),
                  ],
                ),
              ),
            ),
            // ── 让嘎教练点评（预填问题，不自动发送）──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _askCoachToReview,
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('让嘎教练点评'),
                ),
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
