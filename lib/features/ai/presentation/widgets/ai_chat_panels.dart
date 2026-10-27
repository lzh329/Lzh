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

/// 底部输入栏
class AiInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;

  const AiInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Row(
          children: [
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      ),
    );
  }
}
