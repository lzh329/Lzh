import 'package:flutter/material.dart';

import 'package:fittrack/features/settings/presentation/widgets/profile_goals_section.dart';

/// 目标管理页 —— 独立入口（原「目标管理」并入个人档案后，再从档案里拆出）。
///
/// 为什么不留在个人档案里：目标管理本身是完整的一屏（列表 / 新建 / 完成 /
/// 删除），塞进档案会让页面过长、底部留白；独立成页更清爽。
/// 业务逻辑全部在 [ProfileGoalsSection]，本页只提供 Scaffold 外壳。
class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('目标管理'), centerTitle: false),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: ProfileGoalsSection(),
        ),
      ),
    );
  }
}
