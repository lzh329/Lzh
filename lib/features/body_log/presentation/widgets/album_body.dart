import 'package:flutter/material.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/theme/app_colors.dart';

import 'album_action_sheets.dart';
import 'photo_tile.dart';

/// 相册空态
class AlbumEmptyState extends StatelessWidget {
  final VoidCallback onGuide;

  const AlbumEmptyState({super.key, required this.onGuide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                color: AppColors.primary.withAlpha(26),
                borderRadius: BorderRadius.circular(26),
              ),
              child: const Icon(Icons.photo_library,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text('还没有身体照片', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('记录变化，看得见自己的进步',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onGuide,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('拍摄要点'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 相册九宫格：支持对比序号 / 多选勾选 / 分类标签
class AlbumPhotoGrid extends StatelessWidget {
  final List<Photo> photos;
  final bool comparing;
  final bool selecting;
  final Set<int> selectedIds;
  final List<Photo> picked;
  final Future<void> Function() onRefresh;
  final void Function(Photo) onTap;
  final void Function(Photo) onLongPress;

  const AlbumPhotoGrid({
    super.key,
    required this.photos,
    required this.comparing,
    required this.selecting,
    required this.selectedIds,
    required this.picked,
    required this.onRefresh,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          final order = picked.indexWhere((p) => p.id == photo.id) + 1;
          return PhotoTile(
            photo: photo,
            selecting: comparing || selecting,
            checked: selecting && selectedIds.contains(photo.id),
            order: comparing ? (order == 0 ? null : order) : null,
            categoryLabel: photo.category == null
                ? null
                : PhotoCategories.label(photo.category),
            onTap: () => onTap(photo),
            onLongPress: () => onLongPress(photo),
          );
        },
      ),
    );
  }
}
