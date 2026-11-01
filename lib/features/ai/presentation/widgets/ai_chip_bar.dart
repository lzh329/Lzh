import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';

/// 一条 assistant 消息下方的一行动作芯片（C1 / C9）
///
/// 渲染前再过一道白名单：`CoachChip.decode` 已经丢过白名单外的 key，这里是
/// 双保险 —— 芯片 key 一旦漏到 UI，用户点下去就是"没反应"。
class AiChipBar extends StatelessWidget {
  final List<CoachChip> chips;

  /// 本次会话内已点过的 key（C9：置灰不落库，重启复活）
  final Set<String> usedKeys;
  final void Function(CoachChip chip)? onTap;

  const AiChipBar({
    super.key,
    required this.chips,
    this.usedKeys = const {},
    this.onTap,
  });

  /// 工具留痕 / 记忆留痕的消息不挂芯片（C6 的文字判据）
  static bool isTraceText(String text) {
    final t = text.trimLeft();
    return t.startsWith('✅') || t.startsWith('🚫') || t.startsWith('🧠');
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        chips.where((c) => c.isKnown && c.label.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final chip in visible)
            ActionChip(
              label: Text(chip.label, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              backgroundColor: AppColors.background,
              side: const BorderSide(color: AppColors.border),
              // 点过即置灰：芯片是快捷键，不是对话轮次，不能反复触发
              onPressed:
                  usedKeys.contains(chip.key) ? null : () => onTap?.call(chip),
            ),
        ],
      ),
    );
  }
}

/// 芯片点击的唯一落点。
///
/// **不调模型、不写对话历史**（C8）：芯片是快捷键。如果把"点了记体重"当成一条
/// user 消息发出去，模型会回一句"好的记上了" —— 但体重其实还没记（录入框才刚
/// 弹出来），这就制造了"AI 说记好了但没记"的事故，本仓库已经发生过一次。
///
/// 路由**在点击这一刻**解析，不落库：存下来的计划 id 可能已经不存在了。
Future<void> openCoachChip(
  BuildContext context,
  WidgetRef ref,
  CoachChip chip,
) async {
  switch (chip.key) {
    case 'open_workout':
      final plans = await ref.read(planRepoProvider).getAll();
      final active = plans.where((p) => p.isActive).toList();
      if (!context.mounted) return;
      context.push(active.isEmpty
          ? '/workout/quick-start'
          : '/plan/${active.first.id}/execute');
    case 'log_weight':
      // focus=weight：进页面就把焦点落到体重输入框
      context.push('/body?focus=weight');
    case 'log_food':
      // add=1：进页面直接弹录入
      context.push('/diet?add=1');
    case 'set_reminder':
      // 设置页是 ListView，没有锚点机制；做"滚动到提醒区"要跨页传 GlobalKey
      // （脆、难测、收益是一句提示）。P0 落成"进设置页 + 一句提示"。
      context.push('/profile');
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('在「每日提醒」里改时间与开关')),
        );
    case 'open_trends':
      context.push('/trends');
  }
}
