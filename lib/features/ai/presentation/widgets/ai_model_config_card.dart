import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 「当前模型配置」只读信息卡（需求 #8）
///
/// 服务商 / 模型来自设置里选的服务商（[aiProviderById]）；
/// 深度思考是**刻意关闭**的 —— 工具调用模式下开着会稳定 400
/// （见 AiService.disabledThinking 的注释），这里必须写"暂不支持"，
/// 绝对不能提供开关，也不能展示成"可以打开"；
/// 联网搜索是设置页里真实存在的开关，这里只是镜像呈现当前状态。
class AiModelConfigCard extends ConsumerWidget {
  const AiModelConfigCard({super.key, required this.webSearch});

  final bool webSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final provider =
        aiProviderById(ref.watch(userSettingsProvider).valueOrNull?.aiProviderId);
    Row row(String label, String value) => Row(
          children: [
            SizedBox(
              width: 76,
              child: Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary)),
            ),
            Expanded(
              child: Text(value, style: theme.textTheme.bodySmall),
            ),
          ],
        );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前模型配置', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            row('服务商', provider.name),
            const SizedBox(height: 4),
            row('模型', provider.defaultModel),
            const SizedBox(height: 4),
            row('深度思考', '关闭（工具调用模式下暂不支持）'),
            const SizedBox(height: 4),
            row('联网', webSearch ? '开启' : '关闭'),
          ],
        ),
      ),
    );
  }
}
