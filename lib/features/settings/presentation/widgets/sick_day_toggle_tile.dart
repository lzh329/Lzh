import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/presentation/widgets/settings_section.dart';

/// 「今天不舒服」手动开关 —— 这是**必要路径**，不是可选的装饰。
///
/// 没配 AI 的用户也要有这个功能（AI 那条路没配 Key 就根本不存在），
/// 所以本文件的调用链里不出现任何 AI 相关 provider：只碰
/// [sickDayOverrideProvider]，写 `source='user'`。
///
/// 与 AI 写入共用同一行数据、同一个 UI 状态（T03-C8）：用户在界面上看不出
/// 是谁开的，但看得出已经生效。
class SickDayToggleTile extends ConsumerStatefulWidget {
  const SickDayToggleTile({super.key});

  @override
  ConsumerState<SickDayToggleTile> createState() => _SickDayToggleTileState();
}

class _SickDayToggleTileState extends ConsumerState<SickDayToggleTile> {
  /// 上一次拿到的确定值。
  ///
  /// 写库那几毫秒里 AsyncNotifier 是 AsyncLoading，直接读会得到"未生效"，
  /// 开关就会自己弹回去又弹回来 —— 用户看到会以为没生效。这里用上一次的
  /// 确定值盖住那一帧。
  bool _lastActive = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sickDayOverrideProvider);
    if (!async.isLoading) {
      _lastActive = async.valueOrNull != null;
    }

    return SettingsTile(
      icon: Icons.healing,
      color: AppColors.info,
      title: '今天不舒服',
      subtitle:
          _lastActive ? '已生效 · 组数减半、今天不提醒，仅今天有效' : '开启后今天组数减半、提醒暂停，明天自动恢复',
      trailing: Switch(
        value: _lastActive,
        onChanged: (v) async {
          final notifier = ref.read(sickDayOverrideProvider.notifier);
          if (v) {
            await notifier.apply(
              setsScale: 0.5,
              reminderPaused: true,
              source: 'user',
            );
          } else {
            await notifier.revoke();
          }
        },
      ),
    );
  }
}
