import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/workout/presentation/widgets/template_edit_item.dart';

/// 有氧语义：总时长边界 + 动作行存储形态
void main() {
  group('cardioMinutesError：总时长边界（5~180）', () {
    test('5 / 30 / 180 都合法', () {
      expect(cardioMinutesError(5), isNull);
      expect(cardioMinutesError(30), isNull);
      expect(cardioMinutesError(180), isNull);
    });

    test('4 → 提示至少 5 分钟', () {
      expect(cardioMinutesError(4), contains('至少'));
    });

    test('300 → 提示最多 180 分钟（拒绝，不静默截断）', () {
      expect(cardioMinutesError(300), contains('180'));
    });

    test('0 / 负数 → 拒绝', () {
      expect(cardioMinutesError(0), isNotNull);
      expect(cardioMinutesError(-10), isNotNull);
    });
  });

  group('cardioItemValues：有氧动作的存储形态', () {
    test('sets=1、reps=null、durationSec=分钟×60', () {
      final v = cardioItemValues(30);
      expect(v.sets, 1);
      expect(v.reps, isNull, reason: '有氧没有"次数"概念，必须写 null');
      expect(v.durationSec, 30 * 60);
    });

    test('边界值同样按秒换算', () {
      expect(cardioItemValues(5).durationSec, 300);
      expect(cardioItemValues(180).durationSec, 10800);
    });
  });
}
