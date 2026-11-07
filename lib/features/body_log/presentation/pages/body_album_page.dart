import 'dart:io';
import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/presentation/body_log_refresh.dart';
import 'package:fittrack/features/body_log/presentation/widgets/album_action_sheets.dart';
import 'package:fittrack/features/body_log/presentation/widgets/album_app_bar.dart';
import 'package:fittrack/features/body_log/presentation/widgets/album_bars.dart';
import 'package:fittrack/features/body_log/presentation/widgets/album_body.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_compare_page.dart';
import 'package:fittrack/features/body_log/presentation/widgets/photo_preview_dialog.dart';

/// 身体相册 —— 查看 / 拍照 / 批量管理 / 分类 / 前后对比
class BodyAlbumPage extends ConsumerStatefulWidget {
  const BodyAlbumPage({super.key});

  @override
  ConsumerState<BodyAlbumPage> createState() => _BodyAlbumPageState();
}

class _BodyAlbumPageState extends ConsumerState<BodyAlbumPage> {
  final ImagePicker _picker = ImagePicker();
  final List<Photo> _picked = [];
  final Set<int> _selectedIds = {};

  List<Photo> _photos = const [];
  Map<String, double> _weights = const {};
  bool _loading = true;
  bool _busy = false;
  bool _comparing = false;
  bool _selecting = false;

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
      final sorted = List<Photo>.from(photos)
        ..sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _photos = sorted;
        _weights = {for (final m in metrics) photoDayKey(m.date): m.weightKg};
      });
    } catch (_) {
      if (mounted) _snack('照片加载失败，请稍后重试');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── 导入 ──
  Future<void> _takePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 2000, imageQuality: 92);
      if (file == null) return;
      await ref
          .read(photoRepoProvider)
          .addPhoto(date: DateTime.now(), imageFile: File(file.path));
      await _load();
      refreshBodyDependents(ref);
      if (!mounted) return;
      // 拍完不退出：给一个「再拍一张」的入口，连续拍
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('已添加到相册'),
          action: SnackBarAction(label: '再拍一张', onPressed: _takePhoto),
        ));
    } catch (_) {
      if (mounted) _snack('无法打开相机，可从相册导入', offerGallery: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await _picker.pickMultiImage(
          maxWidth: 2000, imageQuality: 92);
      if (files.isEmpty) return;
      final added = await ref.read(photoRepoProvider).addPhotos(
            files: files.map((f) => File(f.path)).toList(),
            date: DateTime.now(),
          );
      if (!mounted) return;
      if (added.isNotEmpty) {
        final category = await showAlbumCategorySheet(context,
            count: added.length);
        if (category != null && category != PhotoCategories.skip) {
          for (final p in added) {
            await ref.read(photoRepoProvider).updateCategory(p.id, category);
          }
        }
      }
      await _load();
      refreshBodyDependents(ref);
      if (mounted) _snack('已添加 ${added.length} 张');
    } catch (_) {
      if (mounted) _snack('照片导入失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, {bool offerGallery = false}) =>
      showAlbumSnack(context, message,
          onGallery: offerGallery ? _importFromGallery : null);

  // ── 选择态 ──
  void _enterCompare() => setState(() {
        _comparing = true;
        _selecting = false;
        _picked.clear();
      });

  void _exitCompare() => setState(() {
        _comparing = false;
        _picked.clear();
      });

  void _enterSelecting() => setState(() {
        _selecting = true;
        _comparing = false;
        _selectedIds.clear();
      });

  void _exitSelecting() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  void _toggleSelect(Photo photo) => setState(() {
        if (!_selectedIds.add(photo.id)) _selectedIds.remove(photo.id);
      });

  void _onTapPhoto(Photo photo) {
    if (_comparing) {
      setState(() {
        final hit = _picked.indexWhere((p) => p.id == photo.id);
        if (hit >= 0) {
          _picked.removeAt(hit);
        } else if (_picked.length < 2) {
          _picked.add(photo);
        }
      });
      return;
    }
    if (_selecting) {
      _toggleSelect(photo);
      return;
    }
    _openPreview(photo);
  }

  Future<void> _onLongPressPhoto(Photo photo) async {
    if (_comparing || _selecting) return;
    final action = await showAlbumPhotoMenu(context, photo.category);
    if (!mounted || action == null) return;
    if (action == 'delete') {
      if (!await confirmDeletePhoto(context)) return;
      await _deletePhoto(photo);
      return;
    }
    try {
      await ref.read(photoRepoProvider).updateCategory(
            photo.id,
            action == PhotoCategories.skip ? null : action,
          );
      await _load();
      refreshBodyDependents(ref);
    } catch (_) {
      if (mounted) _snack('修改分类失败，请稍后重试');
    }
  }

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

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    if (!await confirmDeletePhotos(context, ids.length) || !mounted) return;
    try {
      await ref.read(photoRepoProvider).deleteMany(ids);
    } catch (_) {
      if (mounted) _snack('删除失败，请稍后重试');
      return;
    }
    _exitSelecting();
    await _load();
    refreshBodyDependents(ref);
    if (mounted) _snack('已删除 ${ids.length} 张');
  }

  // ── 预览 / 单张删除 ──
  Future<void> _openPreview(Photo photo) async {
    final deleted = await showPhotoPreview(context, photo);
    if (deleted == true) await _deletePhoto(photo);
  }

  Future<void> _deletePhoto(Photo photo) async {
    try {
      await ref.read(photoRepoProvider).delete(photo.id);
    } catch (_) {
      if (mounted) _snack('删除失败，请稍后重试');
      return;
    }
    await _load();
    if (mounted) _snack('已删除');
    refreshBodyDependents(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AlbumAppBar(
        comparing: _comparing,
        selecting: _selecting,
        busy: _busy,
        canSelect: _photos.isNotEmpty,
        canCompare: _photos.length >= 2,
        onCancel: _comparing ? _exitCompare : _exitSelecting,
        onSelect: _enterSelecting,
        onCompare: _enterCompare,
        onCamera: _takePhoto,
        onGallery: _importFromGallery,
        onGuide: () => showAlbumShootGuide(context),
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
                          ?.copyWith(color: AppColors.textTertiary)),
                ),
                Expanded(
                    child: _photos.isEmpty
                        ? _buildEmptyState()
                        : _buildGrid()),
                if (_comparing)
                  AlbumCompareBar(
                    picked: _picked.length,
                    onCompare: _openCompare,
                    onCancel: _exitCompare,
                  ),
                if (_selecting)
                  AlbumSelectionBar(
                    count: _selectedIds.length,
                    onDelete: _deleteSelected,
                    onCancel: _exitSelecting,
                  ),
              ],
            ),
    );
  }

  Widget _buildEmptyState() =>
      AlbumEmptyState(onGuide: () => showAlbumShootGuide(context));

  Widget _buildGrid() => AlbumPhotoGrid(
        photos: _photos,
        comparing: _comparing,
        selecting: _selecting,
        selectedIds: _selectedIds,
        picked: _picked,
        onRefresh: _load,
        onTap: _onTapPhoto,
        onLongPress: _onLongPressPhoto,
      );
}
