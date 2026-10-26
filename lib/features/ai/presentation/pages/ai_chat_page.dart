import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';

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

    ref.listen(aiChatProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        final msg = next.error!;
        ref.read(aiChatProvider.notifier).consumeError();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(msg)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('嘎教练'),
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
                ? _EmptyHint(onTap: _send, prompts: _quickPrompts)
                : _MessageList(chat: chat),
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
              '免费获取：open.bigmodel.cn 注册后创建 API Key，'
              '模型 GLM-4-Flash 不收费。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: '粘贴以 id- 或 sk- 开头的 Key',
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
  const _MessageList({required this.chat});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (chat.streamingText.isNotEmpty || chat.isStreaming)
        _Bubble.assistant(
          text: chat.streamingText,
          pending: chat.isStreaming && chat.streamingText.isEmpty,
        ),
      ...chat.messages.reversed.map(
        (m) => m.role == 'user'
            ? _Bubble.user(text: m.content)
            : _Bubble.assistant(text: m.content),
      ),
    ];
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      children: children,
    );
  }
}

/// 单条消息气泡
class _Bubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool pending;

  const _Bubble.user({required this.text})
      : isUser = true,
        pending = false;

  const _Bubble.assistant({required this.text, this.pending = false})
      : isUser = false;

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
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: pending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(text, style: TextStyle(color: fg, fontSize: 15, height: 1.5)),
      ),
    );
  }
}

/// 空状态：快捷提问
class _EmptyHint extends StatelessWidget {
  final void Function(String) onTap;
  final List<String> prompts;
  const _EmptyHint({required this.onTap, required this.prompts});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline,
              size: 56, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          const Text('问问嘎教练，它了解你的体重和训练数据',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
              '尚未配置 AI Key（免费）。点右上角钥匙图标，粘贴智谱开放平台的 API Key 即可开始。',
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
