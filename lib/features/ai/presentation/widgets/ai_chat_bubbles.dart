import 'package:flutter/material.dart';

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
class AiChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool pending;
  final String? headAsset;

  const AiChatBubble.user({super.key, required this.text})
      : isUser = true,
        pending = false,
        headAsset = null;

  const AiChatBubble.assistant({
    super.key,
    required this.text,
    this.headAsset,
    this.pending = false,
  }) : isUser = false;

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
    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: pending
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(text, style: TextStyle(color: fg, fontSize: 15, height: 1.5)),
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
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
        ),
      ...messages.reversed.map(
        (m) => m.role == 'user'
            ? AiChatBubble.user(text: m.content)
            : AiChatBubble.assistant(text: m.content, headAsset: headAsset),
      ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      children: children,
    );
  }
}
