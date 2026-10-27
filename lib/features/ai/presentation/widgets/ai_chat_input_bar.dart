import 'dart:io';

import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_panels.dart';

/// 底部输入栏：图片按钮 + 输入框 + 发送按钮
///
/// 语音输入走系统输入法自带的麦克风（本机没有可供第三方调用的识别引擎），
/// 所以这里不再放应用内麦克风按钮。
class AiInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;

  /// 待发送的图片（为空表示纯文本消息）
  final File? image;
  final VoidCallback onPickImage;
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
    final disabled = isStreaming;
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
                  child: AiImageThumbnail(file: image!, onRemove: onRemoveImage),
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: '发送图片',
                  onPressed: disabled ? null : onPickImage,
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 24,
                    color: disabled
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !disabled,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: disabled ? '嘎教练正在回答…' : '向嘎教练提问',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: _roundedBorder(),
                      enabledBorder: _roundedBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 22,
                  backgroundColor:
                      disabled ? AppColors.surfaceAlt : AppColors.primary,
                  child: IconButton(
                    icon: Icon(Icons.send,
                        size: 20,
                        color: disabled
                            ? AppColors.textTertiary
                            : AppColors.onPrimary),
                    onPressed: disabled ? null : onSend,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 输入框圆角描边（聚焦 / 非聚焦同一套，避免切换时边框跳变）
  OutlineInputBorder _roundedBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: AppColors.border),
      );
}
