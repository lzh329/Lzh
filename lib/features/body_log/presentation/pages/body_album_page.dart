import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_compare_page.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_preview_dialog.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_tile.dart';

const _green = Color(0xFF66BB6A);

/// 身体相册 —— 集中查看 / 拍照补充 / 删除 / 前后对比身体照片
class BodyAlbumPage extends ConsumerStatefulWidget {
  const BodyAlbumPage({super.key});

  @override
  ConsumerState<BodyAlbumPage> createState() => _BodyAlbumPageState();
}

class _BodyAlbumPageState extends ConsumerState<BodyAlbumPage> {
  final ImagePicker _picker = ImagePicker();
  final List<Photo> _picked = [];

  List<Photo> _photos = const [];
  Map<String, double> _weights = const {};
  bool _loading = true;
  bool _busy = false;
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 数据 ──
  Future<void> _load() async {
    try {
      final photos = await ref.read(photoRepoProvider).getAll();
      final metrics = await ref.read(bodyMetricRepoProvider).getAll();
      // 仓储已按日期倒序返回，此处再排序一次保证顺序确定
      final sorted = List<Photo>.from(photos)..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _photos = sorted;
        // 日期 → 体重，供对比页标注
        _weights = {for (final m in metrics) photoDayKey(m.date): m.weightKg};
      });
    } catch (_) {
      if (mounted) _snack('照片加载失败，请稍后重试');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── 拍照 / 选图 ──
  Future<void> _takePhoto() =>
      _pickAndSave(ImageSource.camera, '无法打开相机，可从相册选择已有照片');

  Future<void> _pickFromGallery() =>
      _pickAndSave(ImageSource.gallery, '照片选择失败，请稍后重试');

  /// 取图并入库；相机不可用时（模拟器 / 无权限）只提示，不崩溃
  Future<void> _pickAndSave(ImageSource source, String failureHint) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pickImage(source: source, maxWidth: 1440, imageQuality: 88);
      if (file == null) return;
      await ref.read(photoRepoProvider).addPhoto(
          date: DateTime.now(), imageFile: File(file.path));
      await _load();
      if (mounted) _snack('已添加到相册');
    } catch (_) {
      if (mounted) {
        _snack(failureHint, offerGallery: source == ImageSource.camera);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool offerGallery = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: offerGallery
            ? SnackBarAction(label: '从相册选择', onPressed: _pickFromGallery)
            : null,
      ));
  }

  // ── 对比选择态 ──
  void _enterCompare() => setState(() {
        _comparing = true;
        _picked.clear();
      });

  void _exitCompare() => setState(() {
        _comparing = false;
        _picked.clear();
      });

  void _onTapPhoto(Photo photo) {
    if (!_comparing) {
      _openPreview(photo);
      return;
    }
    setState(() {
      final hit = _picked.indexWhere((p) => p.id == photo.id);
      if (hit >= 0) {
        _picked.removeAt(hit);
      } else if (_picked.length < 2) {
        _picked.add(photo);
      }
    });
  }

  /// 选满两张后打开对比页；左早右晚，避免用户选反
  void _openCompare() {
    final first = _picked.first;
    final second = _picked.last;
    final before = first.date.isBefore(second.date) ? first : second;
    final after = before.id == first.id ? second : first;
    _exitCompare();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          PhotoComparePage(before: before, after: after, weights: _weights),
    ));
  }

  Widget _buildCompareBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withAlpha(16))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('已选 ${_picked.length}/2',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          FilledButton.icon(
            onPressed: _picked.length == 2 ? _openCompare : null,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.compare, size: 18),
            label: const Text('开始对比',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_comparing ? '选择对比照片' : '身体相册'),
        centerTitle: false,
        actions: [
          if (_comparing)
            TextButton(onPressed: _exitCompare, child: const Text('取消'))
          else ...[
            IconButton(
              tooltip: '对比照片',
              icon: const Icon(Icons.compare),
              onPressed: _photos.length >= 2 ? _enterCompare : null,
            ),
            IconButton(
              tooltip: '拍照记录',
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: _busy ? null : _takePhoto,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
                  child: Text('共 ${_photos.length} 张',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ),
                Expanded(child: _photos.isEmpty ? _buildEmptyState(theme) : _buildGrid()),
                if (_comparing) _buildCompareBar(theme),
              ],
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: _green.withAlpha(26),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.photo_library, size: 36, color: _green),
            ),
            const SizedBox(height: 18),
            Text('还没有身体照片', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '记录变化，看得见自己的进步',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _photos.length,
        itemBuilder: (context, index) {
          final photo = _photos[index];
          // 已选序号 1/2，未选为 null
          final order = _picked.indexWhere((p) => p.id == photo.id) + 1;
          return PhotoTile(
            photo: photo,
            selecting: _comparing,
            order: order == 0 ? null : order,
            onTap: () => _onTapPhoto(photo),
            onLongPress: _comparing ? null : () => _quickDelete(photo),
          );
        },
      ),
    );
  }

  // ── 预览 / 删除 ──
  /// 预览返回 true 表示用户确认删除
  Future<void> _openPreview(Photo photo) async {
    final deleted = await showPhotoPreview(context, photo);
    if (deleted == true) await _deletePhoto(photo);
  }

  /// 非对比态长按：快速删除（带二次确认）
  Future<void> _quickDelete(Photo photo) async {
    if (!await confirmDeletePhoto(context)) return;
    if (!mounted) return;
    await _deletePhoto(photo);
  }

  /// 删库删文件后刷新列表
  Future<void> _deletePhoto(Photo photo) async {
    try {
      await ref.read(photoRepoProvider).delete(photo.id);
    } catch (_) {
      if (mounted) _snack('删除失败，请稍后重试');
      return;
    }
    await _load();
    if (mounted) _snack('已删除');
  }
}
