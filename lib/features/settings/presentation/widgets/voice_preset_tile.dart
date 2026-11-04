import 'package:flutter/material.dart';

import 'package:fittrack/core/services/voice_presets.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 一张音色预设卡：emoji + 名称 + 一句描述 + 选中态 + 右侧「试听」。
///
/// 从 `cloud_voice_card.dart` 抽出来是为了守住 300 行纪律；
/// 它本身没有状态（"正在试听"由父级传），所以做成 StatelessWidget。
class VoicePresetTile extends StatelessWidget {
  final VoicePreset preset;
  final bool selected;

  /// 是否正在试听这一张（按钮位显示转圈）
  final bool previewing;

  final VoidCallback onTap;
  final VoidCallback onPreview;

  const VoicePresetTile({
    super.key,
    required this.preset,
    required this.selected,
    required this.previewing,
    required this.onTap,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withAlpha(14) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.4 : 0.8,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              Text(preset.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(preset.name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle,
                              size: 13, color: AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(preset.desc,
                        style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.35,
                            color: AppColors.textTertiary)),
                  ],
                ),
              ),
              SizedBox(
                width: 62,
                child: TextButton(
                  onPressed: previewing ? null : onPreview,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: previewing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.6))
                      : const Text('试听', style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}