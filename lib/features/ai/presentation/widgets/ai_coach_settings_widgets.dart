import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/ai_coach_options.dart';

/// 教练设定 / 人设文案页的小组件
/// （抽出来让页面本身保持在 300 行以内）

/// 段落标题
class AiCoachSectionTitle extends StatelessWidget {
  final String text;

  const AiCoachSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}

/// 风格选择卡（遍历 AiCoachOptions.styles 渲染，新增风格自动出现）
class AiCoachStyleCard extends StatelessWidget {
  final AiCoachStyle style;
  final bool selected;
  final VoidCallback onTap;

  const AiCoachStyleCard({
    required this.style,
    required this.selected,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withAlpha(16) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.2 : 0.6,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(style.label,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(style.description,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 人设页顶部说明卡：自定义人设能改什么、不能改什么
class AiPersonaInfoCard extends StatelessWidget {
  const AiPersonaInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withAlpha(60), width: 0.8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.primaryText),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '自定义人设只替换提示词里的「角色」段——规则、输出格式、工具调用与'
              '安全边界都保持不变。留空就使用当前风格的默认人设。',
              style: TextStyle(
                  fontSize: 12, color: AppColors.textPrimary, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

/// 只读展示当前风格默认人设 + 右上角复制按钮
class AiPersonaDefaultCard extends StatelessWidget {
  final String styleLabel;
  final String text;
  final VoidCallback onCopy;

  const AiPersonaDefaultCard({
    super.key,
    required this.styleLabel,
    required this.text,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '风格：$styleLabel',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: '复制默认人设',
                icon: const Icon(Icons.copy_all_outlined,
                    color: AppColors.textTertiary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SelectableText(
              text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// 提示词全文弹窗（可滚动、可复制）
class AiPromptPreviewDialog extends StatelessWidget {
  final String prompt;

  const AiPromptPreviewDialog({super.key, required this.prompt});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('生效的完整提示词', style: TextStyle(fontSize: 16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: SingleChildScrollView(
            child: SelectableText(
              prompt,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.6, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: prompt));
            if (!context.mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            Navigator.of(context).pop();
            messenger.showSnackBar(
              const SnackBar(content: Text('提示词已复制')),
            );
          },
          child: const Text('复制全文'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
