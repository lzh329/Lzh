import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/database/daily_override_repository.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/services/sick_day_gate.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        sickDayGateProvider.overrideWithValue(
          SickDayGate(
            DailyOverrideRepository(db),
            UserSettingsRepositoryImpl(db),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('apply / revoke 后 AsyncNotifier 立刻回到正确状态', () async {
    final notifier = container.read(sickDayOverrideProvider.notifier);
    expect(await container.read(sickDayOverrideProvider.future), isNull);

    await notifier.apply(
      setsScale: 0.5,
      calorieTargetOverride: 2200,
      source: 'ai_health',
    );
    final applied = container.read(sickDayOverrideProvider).value;
    expect(applied, isNotNull, reason: '生效后横幅要立刻出现，不许等下次启动');
    expect(applied!.setsScale, closeTo(0.5, 1e-9));
    expect(applied.calorieTargetOverride, 2200);

    await notifier.revoke();
    expect(container.read(sickDayOverrideProvider).value, isNull,
        reason: '撤销后横幅立刻消失，不靠 invalidate 计数器');
  });

  test('source 非法 → state 记为 AsyncError，异常继续抛给调用方', () async {
    final notifier = container.read(sickDayOverrideProvider.notifier);

    await expectLater(notifier.apply(source: 'sleep'), throwsArgumentError);

    final state = container.read(sickDayOverrideProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isArgumentError);
  });
}
