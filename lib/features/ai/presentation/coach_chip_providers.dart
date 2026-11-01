import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/data/coach_chip_service.dart';

/// 芯片生成（IO + 纯函数规则）。单测可 override 成假实现。
final coachChipServiceProvider = Provider<CoachChipService>((ref) {
  return CoachChipService(
    body: ref.watch(bodyMetricRepoProvider),
    diet: ref.watch(dietRepoProvider),
  );
});
