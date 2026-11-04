import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 架构守卫：`core/` 是底层，**不得反向依赖 `features/`**。
///
/// 只有两个合法例外（组合根 / composition root）：
/// - `core/providers.dart`：Riverpod 的 DI 装配，必然要认识各 feature 的仓储；
/// - `core/router/app_router.dart`：路由装配，必然要认识各 feature 的页面。
///
/// 其余 core 文件（尤其 `core/services/`）一旦 import features，说明这里又变成
/// "知道所有业务"的中枢 —— 历史上一度有 13 个这样的文件（AI/coach 服务、提醒
/// 调度、生病拦截全堆在 core），已全部下沉到对应 feature。这条测试防止回潮。
void main() {
  test('core 不得反向依赖 features（仅 providers.dart / app_router.dart 例外）', () {
    const allowed = {
      'lib/core/providers.dart',
      'lib/core/router/app_router.dart',
    };

    final offenders = <String>[];
    for (final entity in Directory('lib/core').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll('\\', '/');
      if (allowed.contains(rel)) continue;
      final source = entity.readAsStringSync();
      if (source.contains("import 'package:fittrack/features/")) {
        offenders.add(rel);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'core 只应是底层，不能反向 import features。'
          '把业务服务下沉到对应 feature，或把它加进本测试的 allowed 白名单前先问清楚：'
          '它真的是组合根吗？违规文件：$offenders',
    );
  });
}
