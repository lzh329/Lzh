import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/ai/data/ai_tool_executor.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/workout/data/workout_template_repository_impl.dart';
import 'fake_database.dart';

/// delete_template 工具（真内存库 + 全套真仓储，照 ai_body_tools_test 模式）
void main() {
  late AppDatabase db;
  late AiToolExecutor executor;
  late WorkoutTemplateRepositoryImpl templates;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    executor = AiToolExecutor(repos: fakeToolRepos(db));
    templates = WorkoutTemplateRepositoryImpl(db);
  });

  tearDown(() async => db.close());

  Future<int> seed(String name) async {
    final id = await templates.create(
      name: name,
      difficulty: '入门',
      focus: '全身',
      minutes: 20,
      items: const [],
    );
    return id;
  }

  test('在 destructiveTools 里（红卡）且是写工具', () {
    expect(AiToolSpecs.destructiveTools, contains(AiToolSpecs.deleteTemplate));
    expect(AiToolSpecs.writeTools, contains(AiToolSpecs.deleteTemplate));
  });

  test('preview：存在的模板 → needsConfirm + isDestructive + 名称与动作数', () async {
    final id = await seed('平板支撑 90 秒');

    final preview = await executor.preview(AiToolCall(
      id: 'c1',
      name: AiToolSpecs.deleteTemplate,
      argumentsJson: jsonEncode({'id': id}),
    ));

    expect(preview.needsConfirm, isTrue);
    expect(preview.isDestructive, isTrue);
    expect(preview.label, '删除模板');
    expect(preview.detail, contains('平板支撑 90 秒'));
  });

  test('preview：不存在的 id → 抛「找不到模板」（别删空气还报成功）', () async {
    expect(
      () => executor.preview(AiToolCall(
        id: 'c2',
        name: AiToolSpecs.deleteTemplate,
        argumentsJson: jsonEncode({'id': 99999}),
      )),
      throwsA(isA<AiToolException>()),
    );
  });

  test('execute：真删（删后 getById 返回 null）', () async {
    final id = await seed('要删的模板');
    expect(await templates.getById(id), isNotNull);

    final result = await executor.execute(AiToolCall(
      id: 'c3',
      name: AiToolSpecs.deleteTemplate,
      argumentsJson: jsonEncode({'id': id}),
    ));

    final json = jsonDecode(result) as Map<String, dynamic>;
    expect(json['ok'], isTrue);
    expect(json['template_id'], id);
    expect(await templates.getById(id), isNull);
  });
}
