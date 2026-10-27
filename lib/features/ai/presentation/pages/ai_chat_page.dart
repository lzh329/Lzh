import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/services/guga_level.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_input_bar.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_panels.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_tool_confirm_card.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 嘎教练 —— AI 减脂教练聊天页
///
/// - 历史消息 + 流式打字机渲染
/// - 写操作一律弹确认卡（删除类走警示样式）
/// - 数据上下文自动注入（见 AiPromptBuilder）
/// - 支持发图片（视觉提问）
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  /// 待发送的图片（发送后清空）
  File? _image;

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
    final image = _image;
    if (content.isEmpty && image == null) return;
    _inputCtrl.clear();
    if (image != null) setState(() => _image = null);
    ref.read(aiChatProvider.notifier).send(content, image: image);
  }

  /// 选图：底部菜单 → 拍照 / 相册
  Future<void> _pickImage() async {
    final fromCamera = await _showPickSheet();
    if (fromCamera == null) return;
    try {
      final file = await AiChatImageFlow.pick(fromCamera: fromCamera);
      if (file == null || !mounted) return;
      setState(() => _image = file);
    } catch (e) {
      debugPrint('选择图片失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('打开相机/相册失败，检查权限后重试')),
        );
    }
  }

  /// 返回 true=拍照，false=相册，null=取消
  Future<bool?> _showPickSheet() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.textSecondary),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.textSecondary),
              title: const Text('从相册选'),
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(aiChatProvider);
    // 当前咕嘎形态的头像（按累计减重）—— 让对话像咕嘎在说话
    final trends = ref.watch(trendsDataProvider).valueOrNull;
    final stage = GugaLevelService.resolve(trends?.totalLossJin ?? 0).stage;
    final headAsset = stage.asset.replaceFirst('.png', '_head.png');

    ref.listen(aiChatProvider, (prev, next) {
      _startPendingWorkout(next);
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
            GugaAvatar(asset: headAsset, size: 30),
            const SizedBox(width: 8),
            const Text('嘎教练'),
          ],
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '教练设定',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/ai/settings'),
          ),
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
          if (!chat.hasKey) const ApiKeyCard(),
          Expanded(
            child: chat.messages.isEmpty &&
                    chat.streamingText.isEmpty &&
                    chat.pendingTool == null
                ? AiEmptyHint(
                    onTap: _send, prompts: _quickPrompts, headAsset: headAsset)
                : AiMessageList(
                    messages: chat.messages,
                    streamingText: chat.streamingText,
                    isStreaming: chat.isStreaming,
                    headAsset: headAsset,
                  ),
          ),
          if (chat.pendingTool != null)
            AiToolConfirmCard(
              preview: chat.pendingTool!,
              onConfirm: () => ref.read(aiChatProvider.notifier).confirmTool(),
              onCancel: () => ref.read(aiChatProvider.notifier).cancelTool(),
            ),
          AiInputBar(
            controller: _inputCtrl,
            focusNode: _focusNode,
            isStreaming: chat.isBusy,
            image: _image,
            onPickImage: _pickImage,
            onRemoveImage: () => setState(() => _image = null),
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }

  /// 「开始训练」确认后直接进训练页（组数 / 计时已在工具里初始化好）
  ///
  /// 先清空意图再跳转：训练页返回时不会又跳一次。
  void _startPendingWorkout(AiChatState state) {
    final slots = state.pendingWorkoutStart;
    if (slots == null || slots.isEmpty || !mounted) return;
    final name = state.pendingWorkoutTemplateName ?? '训练模板';
    ref.read(aiChatProvider.notifier).consumeWorkoutStart();
    context.push('/workout/active', extra: slots);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已用「$name」开始训练')));
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
