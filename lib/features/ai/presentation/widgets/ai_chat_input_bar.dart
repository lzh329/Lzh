import 'dart:io';

import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/data/ai_voice_input.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_voice_session.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_panels.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_voice_mic_button.dart';

/// 底部输入栏：图片按钮 + 应用内语音输入 + 输入框 + 发送按钮
///
/// 听写状态与文字合并都交给 [AiVoiceSession]，这里只负责按钮样式 / hint 文案。
/// 语音服务通过 [voice] 注入，测试里可换成假实现验证降级提示。
class AiInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isStreaming;
  final VoidCallback onSend;

  /// 待发送的图片（为空表示纯文本消息）
  final File? image;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  /// 可注入的语音服务（默认内部创建；桌面 / 无识别服务时优雅降级）
  final AiVoiceInput? voice;

  const AiInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isStreaming,
    required this.onSend,
    this.image,
    required this.onPickImage,
    required this.onRemoveImage,
    this.voice,
  });

  @override
  State<AiInputBar> createState() => _AiInputBarState();
}

class _AiInputBarState extends State<AiInputBar>
    with SingleTickerProviderStateMixin {
  late final AiVoiceInput _voice = widget.voice ?? AiVoiceInput();
  late final AiVoiceSession _session =
      AiVoiceSession(voice: _voice, controller: widget.controller);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.3,
    upperBound: 1.0,
  );

  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _session.onMessage = _showMessage;
    _session.addListener(_syncListening);
  }

  @override
  void dispose() {
    _session.removeListener(_syncListening);
    _session.cancel();
    _session.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AiInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 开始回答就把还在跑的听写收掉（快捷提问 / 重试没走发送按钮的路径）
    if (widget.isStreaming && !oldWidget.isStreaming && _session.listening) {
      _session.stopForSend();
    }
  }

  /// 听写状态变化：录音中开呼吸动画，结束立刻复位（超时 / 出错也算结束）
  void _syncListening() {
    if (!mounted) return;
    final listening = _session.listening;
    if (listening) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1.0;
    }
    setState(() => _listening = listening);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// 发送：正在听就先停，再交给页面发送
  Future<void> _handleSend() async {
    await _session.stopForSend();
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isStreaming;
    final hint = disabled
        ? '嘎教练正在回答…'
        : (_listening ? '在听…再点一下结束' : '向嘎教练提问');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.image != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AiImageThumbnail(
                    file: widget.image!,
                    onRemove: widget.onRemoveImage,
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: '发送图片',
                  onPressed: disabled ? null : widget.onPickImage,
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 24,
                    color: disabled
                        ? AppColors.textTertiary
                        : AppColors.textSecondary,
                  ),
                ),
                AiVoiceMicButton(
                  listening: _listening,
                  enabled: !disabled,
                  pulse: _pulse,
                  onTap: _session.toggle,
                ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    enabled: !disabled,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: hint,
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
                    onPressed: disabled ? null : _handleSend,
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
