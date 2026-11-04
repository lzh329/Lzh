import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/coach_proactive_providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/presentation/coach_memory_providers.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_coach_settings_widgets.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

/// 「教练的主动性」整段：记忆开关 + 「教练记得的事」入口 + 主动消息开关
/// + 人设文案入口（原本散在教练设定页里的那个 Card，一并搬进来）
///
/// 抽成一段的理由：`ai_coach_settings_page.dart` 已 299 行、贴着 300 行纪律上限。
/// 把 11 行 Card 换成 1 行 `const CoachEngagementSection()`，页面净减、功能净增。
class CoachEngagementSection extends ConsumerWidget {
  const CoachEngagementSection({super.key});

  /// 关闭主动消息的确认文案（PRD 6.3 定稿：不劝阻、不挽留）
  static const turnOffConfirmText = '关了就不再主动说话了。想知道情况的时候，随时来问我。';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider).valueOrNull;
    // 老库 / 首启没有设置行 → 按默认开处理（与 DB 默认值一致）
    final memoryEnabled = settings?.coachMemoryEnabled ?? true;
    final proactiveEnabled = settings?.coachProactiveEnabled ?? true;
    final count = ref.watch(coachMemoryListProvider).valueOrNull?.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AiCoachSectionTitle('教练的主动性'),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                secondary: const Icon(Icons.psychology_outlined,
                    color: AppColors.primary),
                title: const Text('记住我说过的事'),
                subtitle: const Text(
                  '伤病、忌口、作息这些长期情况会自动记住，每次对话一起发给模型',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                ),
                value: memoryEnabled,
                onChanged: (v) =>
                    ref.read(coachMemoryListProvider.notifier).toggleEnabled(v),
              ),
              const Divider(height: 1, indent: 62, endIndent: 16, color: AppColors.border),
              SettingsTile(
                icon: Icons.list_alt_outlined,
                color: AppColors.analysis,
                title: '教练记得的事',
                subtitle: count == null ? '看看它记住了什么，随时删' : '已记住 $count 条，随时可删',
                onTap: () => context.push('/ai/memory'),
              ),
              const Divider(height: 1, indent: 62, endIndent: 16, color: AppColors.border),
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                secondary: const Icon(Icons.campaign_outlined,
                    color: AppColors.warning),
                title: const Text('每周主动说话'),
                subtitle: const Text(
                  '周一早上一条上周总结，只在这台手机上生成',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                ),
                value: proactiveEnabled,
                onChanged: (v) => _toggleProactive(context, ref, v),
              ),
              const Divider(height: 1, indent: 62, endIndent: 16, color: AppColors.border),
              SettingsTile(
                icon: Icons.badge_outlined,
                color: AppColors.analysis,
                title: '人设文案',
                subtitle: '查看并自定义嘎教练的人设（高级）',
                onTap: () => context.push('/ai/persona'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 关掉主动消息要确认（开着不用）—— 关闭是"我以后都不想被找"，值得问一句
  Future<void> _toggleProactive(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    if (!value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭主动消息'),
          content: const Text(turnOffConfirmText),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('再留着')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('关闭', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref
        .read(userSettingsRepoProvider)
        .saveCoachEngagement(proactiveEnabled: value);
    ref.invalidate(userSettingsProvider);
    // 关掉之后立刻撤掉已排的 200；打开则补排（syncPush 只做决策，不生成）
    await ref.read(coachProactiveSchedulerProvider).syncPush();
    ref.invalidate(coachUnreadWeeklyProvider);
    ref.invalidate(coachLatestWeeklyProvider);
    ref.invalidate(coachUnreadRecapProvider);
  }
}
