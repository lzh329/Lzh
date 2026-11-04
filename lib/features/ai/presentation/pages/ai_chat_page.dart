import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/ai_providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart' show AiMessage;
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/ai/data/coach_proactive_providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/presentation/widgets/compare_review_launcher.dart'
    show resolveInitialImage;
import 'package:fittrack/features/ai/data/ai_chat_image_flow.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_notifier.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chip_bar.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_input_bar.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_panels.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_tool_confirm_card.dart';

/// 嘎教练 —— AI 减脂教练聊天页
///
/// - 历史消息 + 流式打字机渲染
/// - 写操作一律弹确认卡（删除类走警示样式）
/// - 数据上下文自动注入（见 AiPromptBuilder）
/// - 支持发图片（视觉提问）
class AiChatPage extends ConsumerStatefulWidget {
  /// 从别处带进来的待发送图片（如对比页的截图）
  final String? initialImagePath;

  /// 预填输入框的文本（**不自动发送**：图像请求要花钱，
  /// 且用户可能想换个问法，别替他做决定）
  final String? initialText;

  const AiChatPage({super.key, this.initialImagePath, this.initialText});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();

  /// 待发送的图片（发送后清空）
  File? _image;

  /// 错误弹窗防重：同一条错误短时间重复触发时不再弹（否则像"卡住不消失"）
  String? _lastErrorMsg;
  DateTime? _lastErrorAt;

  static const _quickPrompts = [
    '用模板开练',
    '今天怎么练？',
    '我吃多了怎么办',
    '点评我的进度',
  ];

  @override
  void initState() {
    super.initState();
    _image = resolveInitialImage(widget.initialImagePath);
    final text = widget.initialText;
    if (text != null && text.isNotEmpty) _inputCtrl.text = text;
  }

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
    // 当前角色的头像 —— 让对话像"陪着他的那个形象"在说话。
    // 路径只从注册表取：以前这里 `replaceFirst('.png', '_head.png')`，
    // 糯糯/菲比根本没有 `_head` 文件 ⇒ 头像白框。
    final spec = ref.watch(currentCharacterProvider);
    final headAsset = spec.avatarAsset;

    // 周消息（「教练说」）作为教练的第一条消息，跟着对话滚动，
    // 而不是固定钉在顶部（之前那张卡片看起来像卡住的横幅）。
    final weekly = ref.watch(coachLatestWeeklyProvider).valueOrNull;
    final displayMessages = <AiMessage>[
      if (weekly != null)
        AiMessage(role: 'assistant', content: weekly.content),
      ...chat.messages,
    ];

    ref.listen(aiChatProvider, (prev, next) {
      _startPendingWorkout(next);
      if (next.error != null && next.error != prev?.error) {
        final msg = next.error!;
        // 防重：同一条错误 3 秒内不重复弹（反复触发会让 SnackBar 看起来"一直停着"）
        final now = DateTime.now();
        if (_lastErrorMsg == msg &&
            _lastErrorAt != null &&
            now.difference(_lastErrorAt!) < const Duration(seconds: 3)) {
          ref.read(aiChatProvider.notifier).consumeError();
          return;
        }
        _lastErrorMsg = msg;
        _lastErrorAt = now;
        ref.read(aiChatProvider.notifier).consumeError();
        final canRetry = !msg.contains('API Key') && !msg.contains('余额');
        // 顶部轻提示，不盖住输入框 / 对话内容（原来底部 SnackBar 会挡住输入区）
        _showErrorToast(msg, canRetry: canRetry);
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
            child: displayMessages.isEmpty &&
                    chat.streamingText.isEmpty &&
                    chat.pendingTool == null
                ? AiEmptyHint(
                    onTap: _send, prompts: _quickPrompts, headAsset: headAsset)
                : AiMessageList(
                    messages: displayMessages,
                    streamingText: chat.streamingText,
                    isStreaming: chat.isStreaming,
                    headAsset: headAsset,
                    usedChipKeys: chat.usedChipKeys,
                    onChipTap: (chip) {
                      // 跳页但不调模型、不写历史（C8）；不再置灰，回来还能再点
                      openCoachChip(context, ref, chip);
                    },
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// 顶部轻提示（错误用）：浮在 AppBar 下方，不占对话 / 输入区空间，自动消失
  void _showErrorToast(String msg, {bool canRetry = false}) {
    final overlay = Overlay.of(context);
    final top = MediaQuery.of(context).padding.top + 8;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Material(
          color: AppColors.textPrimary,
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      msg,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  if (canRetry)
                    TextButton(
                      onPressed: () {
                        entry.remove();
                        ref.read(aiChatProvider.notifier).retryLast();
                      },
                      child: const Text('重试',
                          style: TextStyle(color: AppColors.primary)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (entry.mounted) entry.remove();
    });
  }

  Future<void> _showKeyDialog(bool configured) async {
    final ctrl = TextEditingController();
    final settings = ref.read(userSettingsProvider).valueOrNull;
    var providerId = settings?.aiProviderId ?? 'deepseek';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final provider = aiProviderById(providerId);
          return AlertDialog(
            title: const Text('配置 AI 服务'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: providerId,
                  decoration: const InputDecoration(
                      labelText: '服务商', isDense: true),
                  items: [
                    for (final p in aiProviders)
                      DropdownMenuItem(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => providerId = v ?? 'deepseek'),
                ),
                const SizedBox(height: 12),
                Text(
                  '去 ${provider.keyUrl} 创建 Key（${provider.keyHint}），'
                  '默认模型 ${provider.defaultModel}，按量计费。',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    hintText: '粘贴 API Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref.read(aiChatProvider.notifier).saveAiProvider(providerId);
                  ref.read(aiChatProvider.notifier).saveApiKey(ctrl.text);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
  }
}
