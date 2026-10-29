import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/presentation/widgets/profile_header_card.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/presentation/widgets/my_templates_section.dart';
import 'package:fittrack/features/workout/presentation/widgets/template_cards.dart';

/// 用户实测报的 5 条里，能在 widget 层直接验的三条：
/// 标题行同时显示数量与动作；我的模板收起后 0 张；ProfileHeaderCard 显示昵称。

WorkoutTemplateEntity _t(String name) => WorkoutTemplateEntity(
      id: name.hashCode,
      name: name,
      difficulty: '入门',
      focus: '全身',
      minutes: 20,
    );

void main() {
  testWidgets('标题行同时显示「N 个」与动作按钮（原来二选一）', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TemplateSectionHeader(
          title: '我的模板',
          trailing: '2 个',
          trailingAction: TextButton(
            onPressed: () {},
            child: const Text('收起'),
          ),
        ),
      ),
    ));

    expect(find.text('2 个'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('我的模板 ≤2 个时仍有展开/收起按钮；收起后卡片数 = 0', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MyTemplatesSection(
          templates: [_t('A'), _t('B')],
          starting: false,
          onStart: (_) {},
          onCreate: () {},
          onEdit: (_) {},
        ),
      ),
    ));

    // 两个模板默认展开 → 两张卡
    expect(find.byType(TemplateCard), findsNWidgets(2));
    // 关键：模板只有 2 个也必须能收起
    expect(find.text('收起'), findsOneWidget);

    await tester.tap(find.text('收起'));
    await tester.pump();

    expect(find.byType(TemplateCard), findsNothing,
        reason: '收起 = 全部收掉，不是留 2 张');
    expect(find.text('展开'), findsOneWidget);
  });

  testWidgets('ProfileHeaderCard：有昵称显示昵称，无昵称显示默认名', (tester) async {
    const settings = UserSettingsEntity(
      id: 1,
      lockEnabled: false,
      aiWebSearchEnabled: true,
      aiHealthOverrideCount: 0,
      nickname: '小嘎',
    );
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileHeaderCard(settings: settings)),
    ));
    expect(find.text('小嘎'), findsOneWidget);
    expect(find.text(ProfileHeaderCard.defaultDisplayName), findsNothing);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ProfileHeaderCard()),
    ));
    expect(find.text(ProfileHeaderCard.defaultDisplayName), findsOneWidget);
  });

  test('ProfileHeaderCard.displayName：空串 / 全空格 / "null" 都回落默认名', () {
    UserSettingsEntity withNick(String? n) => UserSettingsEntity(
          id: 1,
          lockEnabled: false,
          aiWebSearchEnabled: true,
          aiHealthOverrideCount: 0,
          nickname: n,
        );
    const card = ProfileHeaderCard();
    expect(card.displayName, ProfileHeaderCard.defaultDisplayName);
    for (final n in ['', '   ', 'null']) {
      final c = ProfileHeaderCard(settings: withNick(n));
      expect(c.displayName, ProfileHeaderCard.defaultDisplayName,
          reason: '"$n" 应视为没设昵称');
    }
    expect(ProfileHeaderCard(settings: withNick(' 小嘎 ')).displayName, '小嘎');
  });

  test('色值常量可用（避免测试因主题常量变动静默失效）', () {
    expect(AppColors.primary, isNotNull);
  });
}
