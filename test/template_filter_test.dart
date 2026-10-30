import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';
import 'package:fittrack/features/workout/domain/template_filter.dart';

WorkoutTemplateEntity _t(String name, String difficulty, String type) =>
    WorkoutTemplateEntity(
      id: name.hashCode,
      name: name,
      difficulty: difficulty,
      focus: '全身', // 已废弃字段，仅占位
      type: type,
      minutes: 20,
      isRecommended: true,
    );

void main() {
  final all = [
    _t('力量入门', '入门', 'strength'),
    _t('力量中阶', '中阶', 'strength'),
    _t('有氧入门', '入门', 'cardio'),
    _t('有氧高阶', '高阶', 'cardio'),
  ];

  group('filterTemplates：类型 × 难度 AND 组合', () {
    test('单选类型（难度全部）：力量', () {
      final r = filterTemplates(all, type: '力量');
      expect(r.map((e) => e.name), ['力量入门', '力量中阶']);
    });

    test('单选类型（难度全部）：有氧', () {
      final r = filterTemplates(all, type: '有氧');
      expect(r.map((e) => e.name), ['有氧入门', '有氧高阶']);
    });

    test('单选难度（类型全部）', () {
      final r = filterTemplates(all, difficulty: '入门');
      expect(r.map((e) => e.name), ['力量入门', '有氧入门']);
    });

    test('两者组合：交集', () {
      final r = filterTemplates(all, type: '有氧', difficulty: '入门');
      expect(r.map((e) => e.name), ['有氧入门']);
      expect(
        filterTemplates(all, type: '力量', difficulty: '高阶'),
        isEmpty,
        reason: '力量没有高阶 → 组合结果为空（UI 把该档置灰）',
      );
    });

    test('都选「全部」→ 原样返回', () {
      expect(filterTemplates(all).length, all.length);
      expect(
        filterTemplates(all, type: kAllFilter, difficulty: kAllFilter).length,
        all.length,
      );
    });

    test('空列表 → 空列表（不抛）', () {
      expect(filterTemplates(const []), isEmpty);
      expect(filterTemplates(const [], type: '力量', difficulty: '入门'), isEmpty);
    });
  });

  group('difficultyCounts：空档置灰的依据', () {
    test('按类型统计各难度档数量', () {
      final counts = difficultyCounts(all, type: '力量');
      expect(counts['入门'], 1);
      expect(counts['中阶'], 1);
      expect(counts['高阶'], 0, reason: '力量没有高阶 → 0 → UI 置灰');
    });

    test('不按当前难度统计（否则选中一档后另外两档会被置灰、无法切回）', () {
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
