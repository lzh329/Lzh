import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/presentation/coach_memory_providers.dart';

/// 「教练记得的事」—— 记忆的可见 / 可删 / 可关（M13 ~ M16）
///
/// 为什么独立成页而不是塞进「教练设定」：后者已 299 行贴着纪律上限；而且
/// 这里要展示"它到底记住了我哪几句"，语义上是 Auditing，不是调参。
class CoachMemoryPage extends ConsumerWidget {
  const CoachMemoryPage({super.key});

  /// 页头定稿文案（决策 6）：必须写明"会随 prompt 发给模型"，否则等于埋雷
  static const headerText = '这些是你在对话里亲口说过的话，教练用它记住你。'
      '每次对话时会一起发给你的 AI 模型（DeepSeek），不经过我们的服务器。'
      '不想要的随时删掉，也可以直接关掉记忆。';

  static const emptyText = '教练还没记住什么。'
      '你在对话里说过的长期情况（伤病、忌口、作息、约定、偏好）会自动记在这里。';

  static const disabledText = '记忆已关闭，教练不会再记新的，也不会用这些。已有的可以删掉。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    final enabled = settings?.coachMemoryEnabled ?? true;
    final async = ref.watch(coachMemoryListProvider);
    final all = async.valueOrNull ?? const <CoachMemory>[];

    return Scaffold(
      appBar: AppBar(title: const Text('教练记得的事')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const Text(
            headerText,
            style: TextStyle(
                fontSize: 12, color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 14),
          if (!enabled) ...[
            Card(
              margin: EdgeInsets.zero,
              color: AppColors.warning.withAlpha(24),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  disabledText,
                  style: TextStyle(fontSize: 12, color: AppColors.warning),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (async.isLoading && all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                emptyText,
                style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textTertiary,
                    height: 1.6),
              ),
            )
          else
            for (final category in kMemoryCategories)
              if (all.any((m) => m.category == category))
                _CategoryGroup(
                  category: category,
                  items: all.where((m) => m.category == category).toList(),
                  dimmed: !enabled,
                ),
          if (all.isNotEmpty) ...[
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => _clearAll(context, ref),
                icon: const Icon(Icons.delete_forever_outlined,
                    size: 18, color: AppColors.danger),
                label: const Text('清除全部记忆',
                    style: TextStyle(fontSize: 13, color: AppColors.danger)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「清除全部记忆」= 真删除（不可撤销）→ **必须**二次确认
  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部记忆'),
        content: const Text('教练会忘掉你所有说过的情况，此操作不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await ref.read(coachMemoryListProvider.notifier).clearAll();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('已清除 $removed 条记忆')));
  }
}

class _CategoryGroup extends ConsumerWidget {
  final String category;
  final List<CoachMemory> items;
  final bool dimmed;

  const _CategoryGroup({
    required this.category,
    required this.items,
    required this.dimmed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '${kMemoryCategoryLabels[category] ?? category} · ${items.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _MemoryRow(item: items[i], dimmed: dimmed),
                  if (i < items.length - 1)
                    const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppColors.border),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryRow extends ConsumerWidget {
  final CoachMemory item;
  final bool dimmed;

  const _MemoryRow({required this.item, required this.dimmed});

  /// 删单条：**不弹确认**，删完 5 秒内可撤销
  ///
  /// 与 T03 决策 3 同源：删除记忆是"回到安全态"，不是破坏性操作。加二次确认
  /// 会让用户懒得清理 —— 而"懒得清理"正是这个功能最坏的结局。
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // ⚠️ 必须在删除**之前**取到 notifier：删掉最后一条时这一行会被 dispose，
    // 之后在 SnackBar 的闭包里再 `ref.read` 会抛
    // 「Cannot use ref after the widget was disposed」——「撤销」按钮直接失效。
    final notifier = ref.read(coachMemoryListProvider.notifier);
    final removed = await notifier.delete(item.id);
    if (removed == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('已删除「${removed.content}」'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => notifier.restore(removed),
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = item.updatedAt;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      title: Text(
        item.content,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: dimmed ? AppColors.textTertiary : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        '${d.year}-${d.month}-${d.day}',
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
      ),
      trailing: IconButton(
        tooltip: '删除',
        icon: const Icon(Icons.close, size: 18, color: AppColors.textTertiary),
        onPressed: () => _delete(context, ref),
      ),
    );
  }
}
