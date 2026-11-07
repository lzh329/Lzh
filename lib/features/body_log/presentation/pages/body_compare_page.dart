import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_empty_state.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_import.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_overlay.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_panel.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_photo_picker.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_review_launcher.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_compare_page.dart'
    show photoDayKey;

/// 身体对比页 —— 并排 / 叠加滑动两种模式，左右可任选照片
class BodyComparePage extends ConsumerStatefulWidget {
  /// 从相册带过来的两张（可选）：传了就直接进入这组对比
  final Photo? initialBefore;
  final Photo? initialAfter;

  const BodyComparePage({super.key, this.initialBefore, this.initialAfter});

  @override
  ConsumerState<BodyComparePage> createState() => _BodyComparePageState();
}

class _BodyComparePageState extends ConsumerState<BodyComparePage> {
  List<Photo> _photos = const [];
  Map<String, double> _weights = const {};
  bool _loading = true;

  Photo? _left;
  Photo? _right;
  bool _overlay = false;
  double _split = 0.5;

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
        if (sorted.length >= 2) {
          final initLeft = widget.initialBefore;
          final initRight = widget.initialAfter;
          final hasInit = initLeft != null &&
              initRight != null &&
              sorted.any((p) => p.id == initLeft.id) &&
              sorted.any((p) => p.id == initRight.id);
          if (hasInit) {
            _setPair(initLeft, initRight);
          } else {
            _left ??= sorted.last;
            _right ??= sorted.first;
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 左早右晚：用户选反了自动交换，避免"变化"读反
  void _setPair(Photo a, Photo b) {
    if (a.date.isAfter(b.date)) {
      _left = b;
      _right = a;
    } else {
      _left = a;
      _right = b;
    }
  }

  double? _weightJin(Photo? p) {
    if (p == null) return null;
    final kg = _weights[photoDayKey(p.date)];
    return kg == null ? null : kg * 2;
  }

  Future<void> _pick(bool isLeft) async {
    final picked = await showComparePhotoPicker(
      context,
      photos: _photos,
      title: isLeft ? '选择较早的那张' : '选择较晚的那张',
      currentId: (isLeft ? _left : _right)?.id,
      weights: _weights,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // 选中的正是另一侧那张 → 直接左右交换（不允许两张相同）
      final other = isLeft ? _right : _left;
      if (other != null && picked.id == other.id) {
        final old = isLeft ? _left : _right;
        if (isLeft) {
          _left = picked;
          _right = old;
        } else {
          _right = picked;
          _left = old;
        }
        if (_left != null && _right != null) _setPair(_left!, _right!);
        return;
      }
      if (isLeft) {
        _setPair(picked, _right ?? picked);
      } else {
        _setPair(_left ?? picked, picked);
      }
    });
  }

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
        return;
      case PhotoImportOutcome.failed:
        final denied = '${result.error}'.toLowerCase().contains('permission');
        _toast(denied
            ? '没有相册权限，去系统设置里允许「照片」后重试'
            : '导入失败：${result.error ?? '未知原因'}');
    }
  }

  /// 截取对比画面，带日期与体重问教练（不自动发送）
  Future<void> _askCoachToReview() async {
    final left = _left;
    final right = _right;
    if (left == null || right == null) return;
    final png = await captureBoundaryPng(_captureKey);
    if (png == null) {
      _toast('截图失败，先自己看看两张照片吧');
      return;
    }
    final file = await writeCompareSnapshot(png);
    if (!mounted) return;
    context.push('/ai/coach', extra: {
      'imagePath': file.path,
      'text': buildCompareReviewPrompt(
        beforeDate: left.date,
        afterDate: right.date,
        beforeJin: _weightJin(left),
        afterJin: _weightJin(right),
      ),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_photos.length < 2 || _left == null || _right == null) {
      return CompareEmptyState(onImport: _importFromGallery);
    }

    final left = _left!;
    final right = _right!;
    final leftJin = _weightJin(left);
    final rightJin = _weightJin(right);
    final days = right.date.difference(left.date).inDays.abs();
    final diffJin =
        (leftJin != null && rightJin != null) ? leftJin - rightJin : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('身体对比'),
        actions: [
          IconButton(
            tooltip: _overlay ? '并排查看' : '滑动对比',
            icon: Icon(_overlay ? Icons.view_column_outlined : Icons.swipe),
            onPressed: () => setState(() => _overlay = !_overlay),
          ),
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
            Expanded(
              child: RepaintBoundary(
                key: _captureKey,
                child: _overlay
                    ? CompareOverlay(
                        before: left,
                        after: right,
                        split: _split,
                        onSplitChanged: (v) => setState(() => _split = v),
                        beforeLabel: compareDateLabel(left, leftJin),
                        afterLabel: compareDateLabel(right, rightJin),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ComparePhotoPanel(
                            photo: left,
                            label: '较早',
                            jin: leftJin,
                            onTap: () => _preview(context, left),
                            onChange: () => _pick(true),
                          ),
                          Container(width: 2, color: AppColors.background),
                          ComparePhotoPanel(
                            photo: right,
                            label: '较晚',
                            jin: rightJin,
                            onTap: () => _preview(context, right),
                            onChange: () => _pick(false),
                          ),
                        ],
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(true),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('换左图'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pick(false),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('换右图'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _askCoachToReview,
                  icon: const Icon(Icons.smart_toy_outlined, size: 18),
                  label: const Text('让嘎教练点评'),
                ),
              ),
            ),
            _buildStats(days: days, diffJin: diffJin),
          ],
        ),
      ),
    );
  }

  Widget _buildStats({required int days, double? diffJin}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('时间跨度',
                    style:
                        TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                Text('$days 天',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
              ],
            ),
          ),
          // 体重变化：两侧都有记录才显示，缺一侧整块不出现（不推测）
          if (diffJin != null) ...[
            Container(width: 1, height: 36, color: AppColors.border),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('体重变化',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textTertiary)),
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
                          color: diffJin > 0 ? _green : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Text('斤',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
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
              child: Image.file(File(photo.filePath), fit: BoxFit.contain),
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
