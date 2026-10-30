import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/theme/app_theme.dart';
import 'package:fittrack/features/ai/domain/ai_tool_inputs.dart';

/// 动作分类只有三类（v23 迁移后）：
/// strength / cardio / stretch —— 任何残留的 bodyweight / gym 都会让
/// 动作库卡片 fallback 成英文 key。
void main() {
  const three = {'strength', 'cardio', 'stretch'};

  test('categoryLabels：三张表 key 一致且只有三类', () {
    expect(AppTheme.categoryLabels.keys.toSet(), three);
    expect(AppTheme.categoryLabels['strength'], '力量');
    expect(AppTheme.categoryLabels['cardio'], '有氧');
    expect(AppTheme.categoryLabels['stretch'], '拉伸');
  });

  test('categoryColors / categoryIcons：同样只有三类', () {
    expect(AppTheme.categoryColors.keys.toSet(), three);
    expect(AppTheme.categoryIcons.keys.toSet(), three);
  });

  test('AI 动作分类：三类 + 旧值归一化到 strength', () {
    expect(AiExerciseCategories.all, three);
    expect(AiExerciseCategories.fallback, 'strength');
    expect(AiExerciseCategories.normalize('bodyweight'), 'strength');
    expect(AiExerciseCategories.normalize('gym'), 'strength');
    expect(AiExerciseCategories.normalize('徒手'), 'strength');
    expect(AiExerciseCategories.normalize('cardio'), 'cardio');
    expect(AiExerciseCategories.normalize('拉伸'), 'stretch');
  });

  test('每个分类都有中文标签（不 fallback 成英文）', () {
    for (final c in three) {
      final label = AppTheme.categoryLabels[c];
      expect(label, isNotNull, reason: '$c 缺标签会显示英文');
      expect(label, isNot(c), reason: '$c 的标签不能等于 key');
    }
  });
}
