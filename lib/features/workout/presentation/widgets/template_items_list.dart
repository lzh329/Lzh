import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'template_edit_item.dart';

/// 「动作（N）」标题 + 空态 / 动作行列表
///
/// 纯展示 + 两个回调（编辑 / 移除），不持有状态 —— 状态留在页面。
class TemplateItemsList extends StatelessWidget {
  final List<EditItem> items;

  /// 有氧模板：行内只显示「时长」，不出现组/次字样
  final bool isCardio;
  final VoidCallback onAdd;
  final void Function(int index) onEdit;
  final void Function(int index) onRemove;

  const TemplateItemsList({
    super.key,
    required this.items,
    this.isCardio = false,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('动作（${items.length}）', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加动作'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        if (items.isEmpty)
          Card(
            margin: const EdgeInsets.only(top: 4),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Center(
                child: Text(
                  '还没有动作，点击「添加动作」从动作库选择',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textTertiary),
                ),
              ),
            ),
          )
        else
          ...items.asMap().entries.map((e) {
            final item = e.value;
            return Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                title: Text(item.name, style: theme.textTheme.bodyMedium),
                subtitle: Text(
                    isCardio
                        ? '${((item.durationSec ?? 0) / 60).round()} 分钟'
                        : item.detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.tune, size: 18),
                      tooltip: '调整组数/次数',
                      onPressed: () => onEdit(e.key),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '移除',
                      onPressed: () => onRemove(e.key),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
