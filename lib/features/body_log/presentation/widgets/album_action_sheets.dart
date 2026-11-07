import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 照片分类取值（与库里的 category 字段一致）
class PhotoCategories {
  static const front = 'front';
  static const side = 'side';
  static const back = 'back';

  /// 跳过 / 清空
  static const skip = 'skip';

  static String label(String? value) {
    switch (value) {
      case front:
        return '正面';
      case side:
        return '侧面';
      case back:
        return '背面';
      default:
        return '未分类';
    }
  }
}

/// 导入后给一批照片分类；返回 'front'/'side'/'back'/'skip'，null = 用户直接关掉
Future<String?> showAlbumCategorySheet(
  BuildContext context, {
  required int count,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('给这 $count 张照片分类',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('分类只用于筛选，之后随时可改',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.textTertiary)),
          ),
          _categoryRow(ctx, PhotoCategories.front, Icons.accessibility_new),
          _categoryRow(ctx, PhotoCategories.side, Icons.directions_walk),
          _categoryRow(ctx, PhotoCategories.back, Icons.airline_seat_recline_normal),
          ListTile(
            leading: const Icon(Icons.skip_next,
                color: AppColors.textTertiary, size: 22),
            title: const Text('跳过分类'),
            onTap: () => Navigator.pop(ctx, PhotoCategories.skip),
          ),
        ],
      ),
    ),
  );
}

Widget _categoryRow(BuildContext ctx, String value, IconData icon) {
  return ListTile(
    leading: Icon(icon, color: AppColors.primary, size: 22),
    title: Text(PhotoCategories.label(value)),
    onTap: () => Navigator.pop(ctx, value),
  );
}

/// 单张照片的长按菜单：改分类 / 删除。返回分类值、'delete' 或 null
Future<String?> showAlbumPhotoMenu(BuildContext context, String? current) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('这张照片',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
          _menuRow(ctx, '设为正面', PhotoCategories.front,
              current == PhotoCategories.front),
          _menuRow(ctx, '设为侧面', PhotoCategories.side,
              current == PhotoCategories.side),
          _menuRow(ctx, '设为背面', PhotoCategories.back,
              current == PhotoCategories.back),
          _menuRow(ctx, '清除分类', PhotoCategories.skip,
              current == null),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_outline,
                color: AppColors.danger, size: 22),
            title: const Text('删除这张',
                style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
}

Widget _menuRow(BuildContext ctx, String label, String value, bool selected) {
  return ListTile(
    title: Text(label),
    trailing: selected
        ? const Icon(Icons.check, size: 18, color: AppColors.primary)
        : null,
    onTap: () => Navigator.pop(ctx, value),
  );
}

/// 拍摄引导：三个角度的要点，**不强制拍齐**
Future<void> showAlbumShootGuide(BuildContext context) {
  const tips = <(String, IconData, String)>[
    ('正面', Icons.accessibility_new, '双脚与肩同宽，手臂自然下垂，镜头与肚脐齐平'),
    ('侧面', Icons.directions_walk, '身体侧转 90°，目视前方，脚跟并拢'),
    ('背面', Icons.airline_seat_recline_normal, '背对镜头，双臂略外展，镜头同样齐脐'),
  ];

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('拍摄要点',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('三个角度任选，不必一次拍齐',
                style: TextStyle(
                    fontSize: 11.5, color: AppColors.textTertiary)),
            const SizedBox(height: 14),
            for (final (name, icon, tip) in tips) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(26),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 20, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(tip,
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.4,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('知道了'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 批量删除二次确认
Future<bool> confirmDeletePhotos(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('删除 $count 张照片？'),
      content: const Text('删除后不可恢复，身体相册与对比页都会同步移除。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return ok == true;
}

/// 相册统一提示（可选带"从相册导入"动作）
void showAlbumSnack(BuildContext context, String message,
    {VoidCallback? onGallery}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: onGallery == null
          ? null
          : SnackBarAction(label: '从相册导入', onPressed: onGallery),
    ));
}
