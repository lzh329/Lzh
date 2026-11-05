import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/providers/today_provider.dart';

/// 「今天」隔夜要推进：首页打卡不能停在昨天
void main() {
  test('① 初值是当天 0 点', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final key = c.read(todayKeyProvider);
    final now = DateTime.now();
    expect(key.hour, 0);
    expect(key.minute, 0);
    expect(key.second, 0);
    expect(key.year, now.year);
    expect(key.month, now.month);
    expect(key.day, now.day);
  });

  test('② 上次是昨天 → 回前台后推进到今天', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final yesterday = todayMidnight().subtract(const Duration(days: 1));
    c.read(todayKeyProvider.notifier).state = yesterday;
    expect(c.read(todayKeyProvider), yesterday);

    // 模拟 resumed
    final changed = applyToday(c.read(todayKeyProvider.notifier));

    expect(changed, isTrue);
    expect(c.read(todayKeyProvider), todayMidnight());
  });

  test('③ 同一天 resume 不产生新值（不白重建下游）', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final before = c.read(todayKeyProvider);
    var notified = 0;
    c.listen(todayKeyProvider, (_, __) => notified++);

    final changed = applyToday(c.read(todayKeyProvider.notifier));

    expect(changed, isFalse, reason: '日期没变就不该写状态');
    expect(notified, 0, reason: '写回同一个值会让下游 provider 白重建');
    expect(c.read(todayKeyProvider), before);
  });

  test('todayMidnight 归一化任意时刻', () {
    final d = DateTime(2026, 3, 4, 23, 59, 59);
    expect(todayMidnight(d), DateTime(2026, 3, 4));
  });
}
