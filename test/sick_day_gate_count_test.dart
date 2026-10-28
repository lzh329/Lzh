import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

/// 计数写入必失败的仓储 —— 用来证明「计数挂了也要把用户放出来」。
class _FailingSettingsRepo extends UserSettingsRepositoryImpl {
  _FailingSettingsRepo(super.db);

  @override
  Future<void> incrementAiHealthOverrideCount() async {
    throw StateError('模拟计数写入失败');
  }
}

void main() {
  late AppDatabase db;
  late DailyOverrideRepository repo;
  late UserSettingsRepositoryImpl settings;
  late SickDayGate gate;

  setUp(() async {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repo = DailyOverrideRepository(db);
    settings = UserSettingsRepositoryImpl(db);
    gate = SickDayGate(repo, settings);
    await settings.save(dailyCalorieTarget: 2000); // 先有设置行，计数才有落点
  });

  tearDown(() async => db.close());

  final day = DateTime(2025, 3, 4);

  Future<int> count() async => (await settings.get())!.aiHealthOverrideCount;

  Future<void> seedAi() =>
      gate.apply(date: day, setsScale: 0.5, source: 'ai_health');

  Future<void> seedUser() =>
      gate.apply(date: day, setsScale: 0.5, source: 'user');

  group('误报计数（user_settings.ai_health_override_count）', () {
    test('T03-F1 初始为 0', () async {
      expect(await count(), 0);
    });

    test('T03-F2 撤销 AI 触发的 → +1', () async {
      await seedAi();
      await gate.revoke(day);
      expect(await count(), 1);
    });

    test('T03-F3 撤销用户自己触发的 → 计数不变', () async {
      await seedUser();
      await gate.revoke(day);
      expect(await count(), 0, reason: '用户自己开自己关，不算 AI 误报');
    });

    test('T03-F4 AI 触发但没被撤销 → 计数不变', () async {
      await seedAi();
      expect(await count(), 0, reason: '跨天自然失效不计，只有用户撤销才算');
    });

    test('T03-F7 连续撤销两次 AI → 是 2 不是 1（原子自增不丢计数）', () async {
      await seedAi();
      await gate.revoke(day);
      await seedAi();
      await gate.revoke(day);
      expect(await count(), 2);
    });

    test('T03-F6 计数单调不减；F5 达到阈值 3；F9 手动清零才归 0', () async {
      for (var i = 0; i < 3; i++) {
        await seedAi();
        await gate.revoke(day);
      }
      expect(await count(), 3);
      expect(3 >= kSickDayFalsePositiveLimit, isTrue, reason: '阈值 3 达成后降级');
      expect(2 >= kSickDayFalsePositiveLimit, isFalse, reason: '2 次还不降级');

      await settings.resetAiHealthOverrideCount();
      expect(await count(), 0, reason: '清零是设置页的手动兜底');
    });

    test('T03-F8 计数写失败 → 撤销照常完成，且不向上抛', () async {
      final failing = SickDayGate(repo, _FailingSettingsRepo(db));
      await failing.apply(date: day, setsScale: 0.5, source: 'ai_health');

      await expectLater(failing.revoke(day), completes,
          reason: '撤销优先于计数：用户不能被困在生病态');

      expect(await repo.getByDate(day), isNull, reason: '覆盖必须真的被删掉');
      expect(await gate.isActive(day), isFalse);
      expect(await count(), 0, reason: '少记一次只是 AI 晚一点降级');
    });
  });
}
