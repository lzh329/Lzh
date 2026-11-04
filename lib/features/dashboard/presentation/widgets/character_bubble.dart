import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';

/// 台词气泡 —— 纯 Flutter widget，**不画进 Rive**（字体/字号/主题色/i18n 失控）
class CharacterBubble extends StatelessWidget {
  const CharacterBubble({
    super.key,
    required this.line,
    required this.isChatEntry,
  });

  final String line;
  final bool isChatEntry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isChatEntry
            ? AppColors.primary.withAlpha(20)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isChatEntry ? AppColors.primary.withAlpha(140) : AppColors.border,
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isChatEntry) ...[
            const Icon(Icons.chat_bubble_outline,
                size: 12, color: AppColors.primaryText),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              line,
              style: TextStyle(
                fontSize: 10.5,
                color: isChatEntry
                    ? AppColors.primaryText
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
