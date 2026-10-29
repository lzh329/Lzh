import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_body_info.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_goals_section.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_identity_card.dart';

/// 个人档案 —— 把原来的「身体信息」页与「目标管理」页合并成一页
///
/// 为什么合并：这两块在用户心里是同一件事（"我的身体"），分成两个入口
/// 只会让人来回找。合并后一屏能看到身份摘要 → 身体信息 → 目标。
///
/// 结构上**没有重写任何业务逻辑**：三块各自是自己那块的状态与校验，
/// 本页只负责把它们排进一个可滚动列表（见 widgets/ 下三个文件头注释）。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(userSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('个人档案')),
      // 只能用 ListView 之外的滚动容器：身体信息那块自己就是 ListView，
      // 嵌进外层 ListView 会要求它 shrinkWrap（性能与手感都差），
      // 所以外层用 SingleChildScrollView + Column，内层靠 physics 关掉自滚。
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ① 身份卡（本轮只读，头像/姓名编辑在第 3 步）
              ProfileIdentityCard(settings: settings),
              const SizedBox(height: 18),

              // ② 身体信息（纯搬运 body_info_page，保存按钮跟着这块走）
              Text('身体信息', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              const ProfileBodyInfo(),
              const SizedBox(height: 22),

              // ③ 目标管理（新建入口在区块标题行右侧，不用 FAB）
              Text('目标管理', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              // 目标区改用「标题 + 右侧新建」后不再需要固定高度：
              // 列表本身跟随内容撑开（新建入口在标题行，不在右下角）
              const ProfileGoalsSection(),
            ],
          ),
        ),
      ),
    );
  }
}
