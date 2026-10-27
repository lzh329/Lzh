import 'dart:io';

import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';

/// 空状态：咕嘎开口说话 + 快捷提问
class AiEmptyHint extends StatelessWidget {
  final void Function(String) onTap;
  final List<String> prompts;
  final String headAsset;

  const AiEmptyHint({
    super.key,
    required this.onTap,
    required this.prompts,
    required this.headAsset,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GugaAvatar(asset: headAsset, size: 76),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border, width: 0.6),
            ),
            child: const Text(
              '我是嘎教练，你的体重、训练、饮食数据我都看着呢。\n想问什么，直接说～',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textPrimary, height: 1.5),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final p in prompts)
                ActionChip(
                  label: Text(p, style: const TextStyle(fontSize: 13)),
                  backgroundColor: AppColors.background,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => onTap(p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 无 Key 时的引导卡
class ApiKeyCard extends StatelessWidget {
  const ApiKeyCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning, width: 0.8),
      ),
      child: const Row(
        children: [
          Icon(Icons.vpn_key_outlined, size: 20, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '尚未配置 AI Key。点右上角钥匙图标，粘贴 DeepSeek 开放平台的 API Key 即可开始。',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部输入栏（左侧图片按钮 + 可选缩略图）
class AiInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;

  /// 待发送的图片（为空表示纯文本消息）
  final File? image;

  /// 点「图片」按钮
  final VoidCallback onPickImage;

  /// 删除待发送的图片
  final VoidCallback onRemoveImage;

  const AiInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.onSend,
    this.image,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ImageThumbnail(
                    file: image!,
                    onRemove: onRemoveImage,
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: '发送图片',
                  onPressed: isStreaming ? null : onPickImage,
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 24,
                    color: isStreaming
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !isStreaming,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: isStreaming ? '嘎教练正在回答…' : '向嘎教练提问',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      isStreaming ? AppColors.surfaceAlt : AppColors.primary,
                  child: IconButton(
                    icon: Icon(Icons.send,
                        size: 20,
                        color: isStreaming
                            ? AppColors.textTertiary
                            : AppColors.onPrimary),
                    onPressed: isStreaming ? null : onSend,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 待发送图片的缩略图（60x60 圆角 + 右上角删除）
class _ImageThumbnail extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const _ImageThumbnail({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            file,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 60,
              height: 60,
              color: AppColors.surfaceAlt,
              child: const Icon(Icons.broken_image_outlined,
                  size: 20, color: AppColors.textTertiary),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
