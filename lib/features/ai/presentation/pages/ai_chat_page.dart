import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 嘎教练 —— AI 减脂教练聊天页
///
/// - 历史消息 + 流式打字机渲染
/// - 无 Key 时引导配置（智谱开放平台，免费）
/// - 数据上下文自动注入（见 AiPromptBuilder）
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  static const _quickPrompts = [
    '今天怎么练？',
    '我吃多了怎么办',
    '点评我的进度',
  ];

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final content = (text ?? _inputCtrl.text).trim();
    if (content.isEmpty) return;
    _inputCtrl.clear();
    ref.read(aiChatProvider.notifier).send(content);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    // 当前咕嘎形态的头像（按累计减重）—— 让对话像咕嘎在说话
    final trends = ref.watch(trendsDataProvider).valueOrNull;
    final stage =
        GugaLevelService.resolve(trends?.totalLossJin ?? 0).stage;
    final headAsset = stage.asset.replaceFirst('.png', '_head.png');

    ref.listen(aiChatProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        final msg = next.error!;
        ref.read(aiChatProvider.notifier).consumeError();
        final canRetry = !msg.contains('API Key') && !msg.contains('余额');
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(msg),
              duration: const Duration(seconds: 5),
              action: canRetry
                  ? SnackBarAction(
                      label: '重试',
                      onPressed: () =>
                          ref.read(aiChatProvider.notifier).retryLast(),
                    )
                  : null,
            ),
          );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GugaAvatar(asset: headAsset, size: 30),
            const SizedBox(width: 8),
            const Text('嘎教练'),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'API Key',
            icon: Icon(
              chat.hasKey ? Icons.key : Icons.key_off_outlined,
              color: chat.hasKey ? AppColors.primary : AppColors.danger,
            ),
            onPressed: () => _showKeyDialog(chat.hasKey),
          ),
          IconButton(
            tooltip: '清空记录',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: chat.messages.isEmpty
                ? null
                : () async {
                    final ok = await _confirmClear();
                    if (ok == true) {
                      await ref.read(aiChatProvider.notifier).clearHistory();
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (!chat.hasKey) const _ApiKeyCard(),
          Expanded(
            child: chat.messages.isEmpty && chat.streamingText.isEmpty
                ? _EmptyHint(
                    onTap: _send, prompts: _quickPrompts, headAsset: headAsset)
                : _MessageList(chat: chat, headAsset: headAsset),
          ),
          _InputBar(
            controller: _inputCtrl,
            focusNode: _focusNode,
            isStreaming: chat.isStreaming,
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmClear() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定删除全部对话吗？此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _showKeyDialog(bool configured) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 API Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '去 platform.deepseek.com 创建 API Key（sk- 开头），'
              '模型 DeepSeek-V4.1-Flash，按量计费，日常聊天每次约几分钱。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: '粘贴 sk- 开头的 Key',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(aiChatProvider.notifier).saveApiKey(ctrl.text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

// ───────────────────── 子组件 ─────────────────────

/// 消息列表（reverse 布局：流式气泡固定在底部）
class _MessageList extends StatelessWidget {
  final AiChatState chat;
  final String headAsset;
  const _MessageList({required this.chat, required this.headAsset});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (chat.streamingText.isNotEmpty || chat.isStreaming)
        _Bubble.assistant(
          text: chat.streamingText,
          headAsset: headAsset,
          pending: chat.isStreaming && chat.streamingText.isEmpty,
        ),
      ...chat.messages.reversed.map(
        (m) => m.role == 'user'
            ? _Bubble.user(text: m.content)
            : _Bubble.assistant(text: m.content, headAsset: headAsset),
      ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      children: children,
    );
  }
}

/// 咕嘎圆形头像（对话里代表"咕嘎在说话"）
class _GugaAvatar extends StatelessWidget {
  final String asset;
  final double size;
  const _GugaAvatar({required this.asset, this.size = 30});

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
class _Bubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool pending;
  final String? headAsset;

  const _Bubble.user({required this.text})
      : isUser = true,
        pending = false,
        headAsset = null;

  const _Bubble.assistant({
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
              child: _GugaAvatar(asset: headAsset!, size: 28),
            ),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// 空状态：咕嘎开口说话 + 快捷提问
class _EmptyHint extends StatelessWidget {
  final void Function(String) onTap;
  final List<String> prompts;
  final String headAsset;
  const _EmptyHint({
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
          _GugaAvatar(asset: headAsset, size: 76),
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
class _ApiKeyCard extends StatelessWidget {
  const _ApiKeyCard();

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
          Icon(Icons.vpn_key_outlined,
              size: 20, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '尚未配置 AI Key。点右上角钥匙图标，粘贴 DeepSeek 开放平台的 API Key 即可开始。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部输入栏
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;

  const _InputBar({
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
