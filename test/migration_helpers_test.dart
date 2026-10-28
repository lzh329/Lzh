import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/migration_helpers.dart';

void main() {
  group('tableExistsIn（纯函数：判断表是否已存在）', () {
    const names = ['exercises', 'user_settings', 'ai_chat_messages'];

    test('命中', () {
      expect(tableExistsIn(names, 'exercises'), isTrue);
      expect(tableExistsIn(names, 'ai_chat_messages'), isTrue);
    });

    test('未命中', () {
      expect(tableExistsIn(names, 'food_log'), isFalse);
      expect(tableExistsIn(names, 'exercise'), isFalse);
    });

    test('大小写不敏感（sqlite 标识符不区分大小写）', () {
      expect(tableExistsIn(names, 'EXERCISES'), isTrue);
      expect(tableExistsIn(names, 'User_Settings'), isTrue);
      expect(tableExistsIn(['WorkoutTemplates'], 'workouttemplates'), isTrue);
    });

    test('空列表返回 false', () {
      expect(tableExistsIn(const <String>[], 'exercises'), isFalse);
      expect(tableExistsIn(const [], ''), isFalse);
    });
  });

  group('columnExistsIn（纯函数：判断列是否已存在）', () {
    const columns = ['id', 'ai_style', 'ai_web_search_enabled'];

    test('命中', () {
      expect(columnExistsIn(columns, 'id'), isTrue);
      expect(columnExistsIn(columns, 'ai_web_search_enabled'), isTrue);
    });

    test('未命中', () {
      expect(columnExistsIn(columns, 'ai_persona_custom'), isFalse);
      expect(columnExistsIn(columns, 'ai_web_search'), isFalse);
    });

    test('大小写不敏感', () {
      expect(columnExistsIn(columns, 'AI_STYLE'), isTrue);
      expect(columnExistsIn(['createdAt'], 'createdat'), isTrue);
    });

    test('空列表返回 false', () {
      expect(columnExistsIn(const <String>[], 'id'), isFalse);
    });
  });

  group('源码守卫：迁移必须走幂等助手', () {
    late String source;

    setUpAll(() {
      source = File('lib/core/database/database.dart').readAsStringSync();
    });

    test('database.dart 里不再出现裸 m.createTable(', () {
      expect(source.contains('m.createTable('), isFalse,
          reason: '建表必须走 createTableIfNotExists，否则半迁移重跑会撞 '
              '"table already exists" 导致启动即死');
    });

    test('database.dart 里不再出现裸 m.addColumn(', () {
      expect(source.contains('m.addColumn('), isFalse,
          reason: '加列必须走 addColumnIfNotExists，否则半迁移重跑会撞 '
              '"duplicate column name"');
    });

    test('建表 / 加列全部经由助手函数', () {
      // 允许调用被 dart format 折行（`addColumnIfNotExists(\n  m, ...`）
      final createCount =
          RegExp(r'createTableIfNotExists\(\s*m,').allMatches(source).length;
      final addCount =
          RegExp(r'addColumnIfNotExists\(\s*m,').allMatches(source).length;
      // v1(userSettings) + v4(foodLibrary, foodLog) + v5(waterLog)
      // + v12(workoutTemplates, workoutTemplateExercises) + v16(aiChatMessages)
      expect(createCount, 7, reason: 'onUpgrade 中的建表点数为 7');
      expect(addCount, greaterThanOrEqualTo(33),
          reason: '所有 addColumn 调用点都应改走 addColumnIfNotExists（当前 33 处）');
    });

    test('onUpgrade 各版本分支仍按 from 递增顺序存在（改造时不许漏分支）', () {
      final upgradeStart = source.indexOf('onUpgrade:');
      expect(upgradeStart, greaterThan(-1), reason: '找不到 onUpgrade 定义');
      final upgradeBody = source.substring(upgradeStart);

      const expectedOrder = [
        'from < 10',
        'from < 11',
        'from < 12',
        'from < 13',
        'from < 14',
        'from < 15',
        'from < 16',
        'from < 17',
        'from < 18',
        'from < 19',
        'from < 20',
      ];

      var cursor = 0;
      for (final branch in expectedOrder) {
        final index = upgradeBody.indexOf('if ($branch)', cursor);
        expect(index, greaterThan(-1),
            reason: '缺少或乱序：$branch（v10→v20 每个分支都必须保留且递增）');
        cursor = index + branch.length;
      }
    });

    test(
      'schemaVersion 单点定义且值为 20（改版本号时只需改这一处 + 本断言）',
      () {
        // 空白无关：dart format 可能把 `=>` 折行，不能依赖换行与缩进
        expect(
          RegExp(r'const\s+int\s+kSchemaVersion\s*=\s*20\s*;')
              .hasMatch(source),
          isTrue,
          reason: '版本号唯一事实来源是 kSchemaVersion 常量',
        );
        expect(
          RegExp(r'int\s+get\s+schemaVersion\s*=>\s*kSchemaVersion\s*;')
              .hasMatch(source),
          isTrue,
          reason: 'AppDatabase.schemaVersion 必须引用常量，不许另写字面量',
        );
      },
    );
  });
}
