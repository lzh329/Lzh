import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/services/ai_service.dart' show AiMessage;
import 'package:fittrack/core/theme/app_colors.dart';

/// 咕嘎圆形头像（对话里代表"咕嘎在说话"）
class GugaAvatar extends StatelessWidget {
  final String asset;
  final double size;

  const GugaAvatar({super.key, required this.asset, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.primary.withAlpha(90), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// 单条消息气泡
///
/// - 助手气泡右下角有复制按钮
/// - 用户气泡长按复制（不占视觉空间）
class AiChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool pending;

  /// 是否显示复制按钮（流式中的气泡不显示，避免边打字边闪）
  final bool canCopy;
  final String? headAsset;

  const AiChatBubble.user({super.key, required this.text})
      : isUser = true,
        pending = false,
        canCopy = true,
        headAsset = null;

  const AiChatBubble.assistant({
    super.key,
    required this.text,
    this.headAsset,
    this.pending = false,
    this.canCopy = true,
  }) : isUser = false;

  /// 复制文本并在页面底部提示（图片消息由调用方传入文字部分）
  Future<void> _copy(BuildContext context) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bg = isUser ? AppColors.primary : AppColors.surfaceAlt;
    final fg = isUser ? AppColors.onPrimary : AppColors.textPrimary;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isUser ? 14 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 14),
    );

    final showCopy = !isUser && canCopy && !pending && text.trim().isNotEmpty;
    final inner = pending
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(text,
                  style: TextStyle(color: fg, fontSize: 15, height: 1.5)),
              if (showCopy) _CopyButton(onTap: () => _copy(context)),
            ],
          );

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: inner,
    );

    if (isUser) {
      // 长按复制：不占额外视觉空间
      return Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _copy(context),
          child: bubble,
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (headAsset != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: GugaAvatar(asset: headAsset!, size: 28),
            ),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// 气泡右下角的迷你复制按钮（低对比、不抢视线）
class _CopyButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CopyButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded,
                  size: 14, color: AppColors.textTertiary.withAlpha(160)),
              const SizedBox(width: 3),
              Text('复制',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary.withAlpha(160),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// 消息列表（reverse 布局：流式气泡固定在底部）
class AiMessageList extends StatelessWidget {
  final List<AiMessage> messages;
  final String streamingText;
  final bool isStreaming;
  final String headAsset;

  const AiMessageList({
    super.key,
    required this.messages,
    required this.streamingText,
    required this.isStreaming,
    required this.headAsset,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (streamingText.isNotEmpty || isStreaming)
        AiChatBubble.assistant(
          text: streamingText,
          headAsset: headAsset,
          pending: isStreaming && streamingText.isEmpty,
          canCopy: !isStreaming,
        ),
      ...messages.reversed.map(
        (m) => m.role == 'user'
            // 图片消息只展示文字部分（历史里本来也只存了文字）
            ? AiChatBubble.user(text: m.textOnly)
            : AiChatBubble.assistant(text: m.textOnly, headAsset: headAsset),
      ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      children: children,
    );
  }
}
