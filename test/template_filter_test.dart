import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';

WorkoutTemplateEntity _t(String name, String focus, String difficulty) =>
    WorkoutTemplateEntity(
      id: name.hashCode,
      name: name,
      difficulty: difficulty,
      focus: focus,
      minutes: 20,
      isRecommended: true,
    );

void main() {
  final all = [
    _t('全身入门', '全身', '入门'),
    _t('全身中阶', '全身', '中阶'),
    _t('放松入门', '放松', '入门'),
    _t('碎片高阶', '碎片', '高阶'),
  ];

  group('filterTemplates：场景 × 难度 AND 组合', () {
    test('单选场景（难度全部）', () {
      final r = filterTemplates(all, focus: '全身');
      expect(r.map((e) => e.name), ['全身入门', '全身中阶']);
    });

    test('单选难度（场景全部）', () {
      final r = filterTemplates(all, difficulty: '入门');
      expect(r.map((e) => e.name), ['全身入门', '放松入门']);
    });

    test('两者组合：交集', () {
      final r = filterTemplates(all, focus: '放松', difficulty: '入门');
      expect(r.map((e) => e.name), ['放松入门']);
      expect(
        filterTemplates(all, focus: '全身', difficulty: '高阶'),
        isEmpty,
        reason: '全身没有高阶 → 组合结果应为空（UI 会把该档置灰）',
      );
    });

    test('都选「全部」→ 原样返回', () {
      expect(filterTemplates(all).length, all.length);
      expect(
        filterTemplates(all, focus: kAllFilter, difficulty: kAllFilter).length,
        all.length,
      );
    });

    test('空列表 → 空列表（不抛）', () {
      expect(filterTemplates(const []), isEmpty);
      expect(filterTemplates(const [], focus: '全身', difficulty: '入门'), isEmpty);
    });
  });

  group('difficultyCounts：空档置灰的依据', () {
    test('按场景统计各难度档数量', () {
      final counts = difficultyCounts(all, focus: '全身');
      expect(counts['入门'], 1);
      expect(counts['中阶'], 1);
      expect(counts['高阶'], 0, reason: '全身没有高阶 → 0 → UI 置灰');
    });

    test('不按当前难度统计（否则选中一档后另外两档会被置灰、无法切回）', () {
      // 只传 focus：入门 2 个、中阶 1 个、高阶 1 个
      final counts = difficultyCounts(all);
      expect(counts['入门'], 2);
      expect(counts['中阶'], 1);
      expect(counts['高阶'], 1);
    });

    test('三档恒定出现在结果里（固定枚举，永远显示）', () {
      expect(difficultyCounts(const []).keys, kDifficultyOrder);
      expect(difficultyCounts(const []).values, everyElement(0));
    });
  });
}
