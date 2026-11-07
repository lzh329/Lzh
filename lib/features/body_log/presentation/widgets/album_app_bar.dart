import 'package:flutter/material.dart';

/// 相册顶栏：普通态（选择/对比/拍照/更多）、对比态、多选态
class AlbumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool comparing;
  final bool selecting;
  final bool busy;
  final bool canSelect;
  final bool canCompare;
  final VoidCallback onCancel;
  final VoidCallback onSelect;
  final VoidCallback onCompare;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onGuide;

  const AlbumAppBar({
    super.key,
    required this.comparing,
    required this.selecting,
    required this.busy,
    required this.canSelect,
    required this.canCompare,
    required this.onCancel,
    required this.onSelect,
    required this.onCompare,
    required this.onCamera,
    required this.onGallery,
    required this.onGuide,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final editing = comparing || selecting;
    return AppBar(
      title: Text(comparing ? '选择对比照片' : (selecting ? '选择照片' : '身体相册')),
      centerTitle: false,
      actions: [
        if (editing)
          TextButton(onPressed: onCancel, child: const Text('取消'))
        else ...[
          IconButton(
            tooltip: '批量选择',
            icon: const Icon(Icons.checklist),
            onPressed: canSelect ? onSelect : null,
          ),
          IconButton(
            tooltip: '对比照片',
            icon: const Icon(Icons.compare),
            onPressed: canCompare ? onCompare : null,
          ),
          IconButton(
            tooltip: '拍照记录',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: busy ? null : onCamera,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'gallery' ? onGallery() : onGuide(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'gallery', child: Text('从相册导入（可多选）')),
              PopupMenuItem(value: 'guide', child: Text('拍摄要点')),
            ],
          ),
        ],
      ],
    );
  }
}
