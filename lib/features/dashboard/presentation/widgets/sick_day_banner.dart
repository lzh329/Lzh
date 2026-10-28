import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 生病模式横幅：生效当天挂在首页顶部，撤销按钮就长在它上面。
///
/// 文案必须说清三件事，少一件都会让用户第二天以为数据错了：
/// ① 今天是生病模式；
/// ② 具体改了什么（有什么说什么，没有的别编）；
/// ③ **仅今天有效，明天自动恢复** —— 覆盖是按天存的，这是实现细节用户不知道，
///    不写这句的话用户会把临时状态当成持久设置，第二天提醒又响、组数又变了，
///    第一反应就是「数据错了」。这种投诉最难解释，也最伤信任。
class SickDayBanner extends ConsumerWidget {
  const SickDayBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = ref.watch(sickDayOverrideProvider).valueOrNull;
    if (override == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: AppColors.warning.withAlpha(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(32),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.healing,
                      size: 14, color: AppColors.warning),
                ),
                const SizedBox(width: 8),
                const Text(
                  '生病模式',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                // 撤销**不弹二次确认**：撤销是回到安全状态，不是破坏性操作，
                // 把「救回数据」做得比「改数据」还难是本末倒置。
                TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(sickDayOverrideProvider.notifier).revoke();
                    } catch (_) {
                      // 失败时 AsyncNotifier 已把 state 记为 AsyncError，
                      // 这里只负责不让异常冒到 Flutter 框架里变成崩溃。
                    }
                  },
                  child: const Text('撤销'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _effectText(override),
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
            ),
            const SizedBox(height: 2),
            Text(
              '仅今天有效，明天自动恢复',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ② 具体改了什么：有什么说什么，没有的别编。
  ///
  /// 一条都没有（行存在但三个字段都没设）时只说"放松执行"，
  /// 不替用户脑补"我猜你应该是发烧了"。
  static String _effectText(DailyOverride o) {
    final parts = <String>[];

    final scale = o.setsScale;
    if (scale != null) {
      parts.add('训练组数按 ${(scale * 100).round()}% 执行');
    }

    final cal = o.calorieTargetOverride;
    if (cal != null) {
      parts.add('热量目标放宽到 $cal 千卡');
    }

    if (o.reminderPaused) {
      parts.add('今天训练和称重提醒都不响');
    }

    if (parts.isEmpty) return '今天按生病模式放松执行';
    return parts.join(' · ');
  }
}
