import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';
import 'package:fittrack/features/ai/presentation/coach_memory_providers.dart';

/// 「教练记得的事」的异步状态
///
/// 写操作全部走这里：删（可撤销）/ 撤销 / 清空 / 开关。
/// **删单条不弹确认**（回到安全态，不是破坏性操作），**清空必须二次确认**
/// （不可撤销）—— 由页面负责弹框，Notifier 只执行。
class CoachMemoryNotifier extends AsyncNotifier<List<CoachMemory>> {
  @override
  Future<List<CoachMemory>> build() {
    return ref.watch(coachMemoryServiceProvider).listAll();
  }

  /// 删单条，返回被删的行供 5 秒撤销
  Future<CoachMemory?> delete(int id) async {
    final removed = await ref.read(coachMemoryServiceProvider).deleteById(id);
    await _refresh();
    return removed;
  }

  Future<void> restore(CoachMemory memory) async {
    await ref.read(coachMemoryServiceProvider).restore(memory);
    await _refresh();
  }

  /// 清除全部记忆（页面已二次确认）
  Future<int> clearAll() async {
    final removed = await ref.read(coachMemoryServiceProvider).clearAll();
    await _refresh();
    return removed;
  }

  /// 记忆开关：关掉不写不注入不留痕，**数据保留**（关 ≠ 删）
  Future<void> toggleEnabled(bool value) async {
    await ref.read(userSettingsRepoProvider).saveCoachEngagement(
          memoryEnabled: value,
        );
    ref.invalidate(userSettingsProvider);
    await _refresh();
  }

  /// 写库 → 回读 → 落 state（与 T03 的 SickDayOverrideNotifier 同思路：
  /// 不靠手动版本号、不靠 invalidate 计数器）
  Future<void> _refresh() async {
    state = AsyncData(await ref.read(coachMemoryServiceProvider).listAll());
  }
}
