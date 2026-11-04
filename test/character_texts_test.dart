import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_tasks_card.dart';

/// C-18（debug 页脚）/ C-19（称呼口径）/ C-20（字面量「咕嘎」清零）
void main() {
  group('C-19 问候语用角色名，不带形态名、不带括号', () {
    testWidgets('糯糯：问候语含「糯糯」，不含「（」与「版）」', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GreetingHeader(
            streakDays: 3,
            characterName: '糯糯',
            avatarAsset: 'assets/characters/nuonuo_1.png',
          ),
        ),
      ));

      final greeting = find.textContaining('糯糯');
      expect(greeting, findsOneWidget);
      final text = tester.widget<Text>(greeting).data!;
      expect(text.contains('（'), isFalse,
          reason: '「晚上好，糯糯（蓝发版）」在中文里读不通，还会挤成两行');
      expect(text.contains('版）'), isFalse);
      // 问候语 = 「{问候}，糯糯」
      expect(text.endsWith('，糯糯'), isTrue);
    });

    testWidgets('咕嘎：问候语是「{问候}，咕嘎」', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GreetingHeader(
            characterName: '咕嘎',
            avatarAsset: 'assets/guga3d/guga_fat_head.png',
          ),
        ),
      ));

      final text = tester
          .widget<Text>(find.textContaining('咕嘎'))
          .data!;
      expect(text.endsWith('，咕嘎'), isTrue);
    });

    testWidgets('设了昵称就用昵称（优先级最高）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GreetingHeader(nickname: '小嘎', characterName: '糯糯'),
        ),
      ));

      expect(find.textContaining('小嘎'), findsOneWidget);
      expect(find.textContaining('糯糯'), findsNothing,
          reason: '昵称是用户自己写的，优先于角色名');
    });
  });

  group('C-20 用户可见的「咕嘎」字面量清零', () {
    test('四个渲染位的源码里没有写死的「咕嘎」（注释除外）', () {
      const files = [
        'lib/features/dashboard/presentation/widgets/today_tasks_card.dart',
        'lib/features/dashboard/presentation/widgets/greeting_header.dart',
        'lib/features/trends/presentation/widgets/companion_card.dart',
        'lib/features/ai/presentation/pages/ai_chat_page.dart',
      ];
      for (final path in files) {
        final code = File(path)
            .readAsStringSync()
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('咕嘎'), isFalse, reason: '$path 里还有字面量「咕嘎」');
      }
    });

    testWidgets('糯糯下今日任务完成文案为「今日全部完成，糯糯为你鼓掌！」', (tester) async {
      await initializeDateFormatting('zh_CN');
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TodayTasksCard(
            todayWeightJin: 60,
            latestWeightJin: 60,
            hasTraining: true,
            workoutCount: 1,
            photoDone: true,
            characterName: '糯糯',
            onWeight: _noop,
            onWorkout: _noop,
            onPhoto: _noop,
          ),
        ),
      ));

      expect(find.text('今日全部完成，糯糯为你鼓掌！'), findsOneWidget);
      expect(find.text('今日全部完成，咕嘎为你鼓掌！'), findsNothing);
    });

    testWidgets('咕嘎下文案仍是「咕嘎为你鼓掌」（默认角色不受影响）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: TodayTasksCard(
            todayWeightJin: 60,
            latestWeightJin: 60,
            workoutCount: 1,
            photoDone: true,
            characterName: '咕嘎',
            onWeight: _noop,
            onWorkout: _noop,
            onPhoto: _noop,
          ),
        ),
      ));

      expect(find.text('今日全部完成，咕嘎为你鼓掌！'), findsOneWidget);
    });
  });

  group('C-9 / C-18 形态名与解锁提示的措辞', () {
    test('形象页卡标题用的是形态名，且只说「样子」不说「形态」', () {
      final spec = CharacterCatalog.resolve('nuonuo', 0);
      expect(spec.formName, '糯糯（玩偶版）');
      expect(spec.isMaxForm, isFalse);
      expect(spec.nextFormName, '糯糯（蓝发版）');
    });

    test('与趋势页同名的「累计减重」不出现在形象页文案里', () {
      // 形象页/解锁提示只允许「再减 X 斤，换下一个样子」措辞（风险 3）
      final source = File(
              'lib/features/settings/presentation/pages/character_page.dart')
          .readAsStringSync();
      expect(source.contains('累计减重'), isFalse,
          reason: '形象页用"再减 X 斤"，趋势页用"累计减重"，两个数字口径不同');
      expect(source, contains('kRemainToNextForm'));
    });

    testWidgets('首页问候的解锁提示也用「再减 X 斤换下一个样子」', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GreetingHeader(
            characterName: '糯糯',
            upgradeHint: '再减 1.4 斤换下一个样子',
          ),
        ),
      ));
      expect(find.textContaining('换下一个样子'), findsOneWidget);
      expect(find.textContaining('距升级'), findsNothing,
          reason: '旧措辞「距升级」已废弃（形态是"样子"，不是"等级"）');
    });
  });
}

void _noop() {}
