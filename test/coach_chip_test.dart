import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/ai_service.dart';
import 'package:fittrack/features/ai/data/ai_chat_repository.dart';
import 'package:fittrack/features/ai/domain/coach_chip.dart';
import 'package:fittrack/features/ai/domain/coach_chip_rules.dart';
import 'package:fittrack/features/ai/presentation/notifiers/ai_chat_state.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_bubbles.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chip_bar.dart';

import 'fake_database.dart';

/// 动作芯片（C 组 9 条）
///
/// 芯片的规则是纯函数，所以 C-2~C-5 不用 mock、不用库；只有持久化（C-7）
/// 与渲染（C-1/C-6/C-9）需要真的库和真的 widget。
void main() {
  // ═══════════ C-1：白名单 ═══════════

  group('C-1 白名单', () {
    test('decode 丢掉白名单外的 key', () {
      final chips = CoachChip.decode('[{"k":"open_workout"},{"k":"hack"}]');
      expect(chips, hasLength(1));
      expect(chips.single.key, 'open_workout');
      expect(kCoachChipKeys, {
        'open_workout',
        'log_weight',
        'log_food',
        'set_reminder',
        'open_trends',
      });
    });

    test('null / 空串 / 非法 JSON → 空列表（老数据兼容，无需 backfill）', () {
      expect(CoachChip.decode(null), isEmpty);
      expect(CoachChip.decode(''), isEmpty);
      expect(CoachChip.decode('not json'), isEmpty);
      expect(CoachChip.decode('{"k":"log_weight"}'), isEmpty, reason: '必须是数组');
    });

    test('encode：空列表 → null（不写 "[]"）', () {
      expect(CoachChip.encode(const []), isNull);
      expect(CoachChip.encode(const [CoachChip('hack')]), isNull,
          reason: '白名单外的 key 不许落库');
      expect(CoachChip.encode(const [CoachChip('log_weight')]),
          contains('"k":"log_weight"'));
    });

    testWidgets('widget：传入白名单外 key 只渲染 1 个芯片', (tester) async {
      await _pump(
        tester,
        const AiChipBar(
          chips: [CoachChip('open_workout'), CoachChip('hack')],
        ),
      );
      expect(find.byType(ActionChip), findsOneWidget);
      expect(find.text('去开练'), findsOneWidget);
    });
  });

  // ═══════════ C-2 / C-3 / C-4 / C-5：6 条规则 ═══════════

  group('C-2 六条规则各自可测', () {
    List<String> keys({
      String text = '',
      List<String> receipts = const [],
      bool weight = false,
      bool food = false,
    }) =>
        CoachChipRules.build(
          assistantText: text,
          toolReceipts: receipts,
          hasWeightToday: weight,
          hasFoodToday: food,
        ).map((c) => c.key).toList();

    test('① start_workout 回执 ok:false → 去开练', () {
      expect(
        keys(receipts: [
          'start_workout:{"ok":false,"error":"没找到模板「燃脂」"}',
        ]),
        ['open_workout'],
      );
    });

    test('① 只有 ok:true 的回执 → 不出芯片（工具成功了没什么要补的）', () {
      expect(
        keys(receipts: ['start_workout:{"ok":true,"template_name":"燃脂"}']),
        isEmpty,
      );
    });

    test('① 别的工具失败不该触发「去开练」', () {
      expect(
        keys(receipts: ['log_food:{"ok":false,"error":"用户取消"}']),
        isEmpty,
      );
    });

    test('② 正文含「开练」→ 去开练', () {
      expect(keys(text: '想练就直接开练吧'), ['open_workout']);
      expect(keys(text: '用这个模板就行'), ['open_workout']);
    });

    test('③ 正文含「体重」且今日无记录 → 记体重', () {
      expect(keys(text: '该称体重了'), ['log_weight']);
      expect(keys(text: '该称体重了', weight: true), isEmpty, reason: 'C5');
    });

    test('④ 正文含「蛋白」且今日无饮食记录 → 记饮食', () {
      expect(keys(text: '今天蛋白吃少了'), ['log_food']);
      expect(keys(text: '今天蛋白吃少了', food: true), isEmpty, reason: 'C5');
    });

    test('⑤ 正文含「提醒」→ 设提醒', () {
      expect(keys(text: '要不要定个提醒'), ['set_reminder']);
    });

    test('⑥ 正文含「上周」→ 看趋势', () {
      expect(keys(text: '上周比前一周好'), ['open_trends']);
    });
  });

  test('C-3：命中 4 条只出 3 条且按优先级（同 key 不重复）', () {
    final chips = CoachChipRules.build(
      assistantText: '这周该称体重了，记得多吃蛋白，定个提醒，看看上周趋势',
      toolReceipts: const [],
      hasWeightToday: false,
      hasFoodToday: false,
    );
    expect(chips, hasLength(3));
    expect(chips.map((c) => c.key).toList(),
        ['log_weight', 'log_food', 'set_reminder']);
  });

  test('C-3：同一 key 不重复（正文同时命中「开练」和「模板」）', () {
    final chips = CoachChipRules.build(
      assistantText: '直接开练，用这个模板',
      toolReceipts: const [],
      hasWeightToday: false,
      hasFoodToday: false,
    );
    expect(chips.where((c) => c.key == 'open_workout'), hasLength(1));
  });

  test('C-4：一条都不命中 → 空列表，不给兜底芯片', () {
    final chips = CoachChipRules.build(
      assistantText: '嗯，是这么回事',
      toolReceipts: const [],
      hasWeightToday: false,
      hasFoodToday: false,
    );
    expect(chips, isEmpty);
  });

  // ═══════════ C-6 / C-9：渲染 ═══════════

  testWidgets('C-6：工具留痕 / 记忆留痕消息不挂芯片', (tester) async {
    for (final text in [
      '✅ 已执行：开始训练：燃脂',
      '🚫 已取消：记饮食',
      '🧠 已记住：右膝有旧伤',
    ]) {
      await _pump(
        tester,
        AiChatBubble.assistant(
          text: text,
          chips: const [CoachChip('open_workout')],
        ),
      );
      expect(find.byType(ActionChip), findsNothing, reason: '留痕消息不该有芯片：$text');
    }
  });

  testWidgets('C-6：流式中（pending）不挂芯片', (tester) async {
    await _pump(
      tester,
      const AiChatBubble.assistant(
        text: '',
        pending: true,
        chips: [CoachChip('open_workout')],
      ),
    );
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('C-9：点过的芯片置灰（onPressed == null）', (tester) async {
    await _pump(
      tester,
      const AiChipBar(
        chips: [CoachChip('log_weight'), CoachChip('open_trends')],
        usedKeys: {'log_weight'},
      ),
    );
    final chips =
        tester.widgetList<ActionChip>(find.byType(ActionChip)).toList();
    expect(chips, hasLength(2));
    expect(chips.first.onPressed, isNull, reason: '点过即置灰，本次会话内不可再点');
    expect(chips.last.onPressed, isNotNull);
  });

  // ═══════════ C-7：持久化 ═══════════

  test('C-7：芯片随消息落库，重启后 getHistory 解析回来；老行 NULL → 空列表', () async {
    final db = fakeDatabase();
    addTearDown(db.close);
    final repo = AiChatRepository(db);

    await repo.add('assistant', '今天蛋白吃少了，记一下',
        chips: const [CoachChip('log_food')]);
    final history = await repo.getHistory();
    expect(history.single.chips.map((c) => c.key).toList(), ['log_food']);

    // 老数据：chips 为 NULL
    await db.into(db.aiChatMessages).insert(
        AiChatMessagesCompanion.insert(role: 'assistant', content: '老消息'));
    final all = await repo.getHistory();
    expect(all.last.chips, isEmpty);

    // 没有芯片的消息不写 '[]'
    final rows = await db.select(db.aiChatMessages).get();
    expect(rows.last.chips, isNull);
  });

  // ═══════════ 传输层红线 ═══════════

  test('AiMessage.toJson() 绝不能带 chips（带出去会污染 prompt 甚至 400）', () {
    const msg = AiMessage(
      role: 'assistant',
      content: '练完了',
      chips: [CoachChip('open_workout')],
    );
    final json = msg.toJson();
    expect(json.containsKey('chips'), isFalse);
    expect(json['role'], 'assistant');
    expect(json['content'], '练完了');
  });

  test('AiChatState.markChipUsed 只加 key，不动消息', () {
    final state = const AiChatState().markChipUsed('log_weight');
    expect(state.usedChipKeys, {'log_weight'});
    expect(state.messages, isEmpty);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}
