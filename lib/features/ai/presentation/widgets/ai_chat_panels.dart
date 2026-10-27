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


/// 待发送图片的缩略图（60x60 圆角 + 右上角删除）
class AiImageThumbnail extends StatelessWidget {
  final File file;
  final VoidCallback onRemove;

  const AiImageThumbnail({super.key, required this.file, required this.onRemove});

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
