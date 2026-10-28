import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fittrack/core/database/db_replaced_marker.dart';
import 'package:fittrack/core/theme/app_theme.dart';

/// 封存页：库文件已被替换，当前连接不可再信任 → 必须重启。
///
/// 三条硬要求：
/// 1. **不可返回**（`PopScope(canPop: false)` + 无导航栈入口）：回到任何页面
///    都只会读到"已被替换的旧库"，让用户以为数据丢了。
/// 2. 只给**一个**出口：「退出」，让用户重开 App 加载新数据。
/// 3. 小字说明「重新打开后加载新数据」—— 用户需要知道这不是故障，而是最后一步。
class DatabaseSealedApp extends StatelessWidget {
  final String? detail;

  const DatabaseSealedApp({super.key, this.detail});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '减肥嘎',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: DatabaseSealedPage(detail: detail),
    );
  }
}

class DatabaseSealedPage extends StatelessWidget {
  final String? detail;

  const DatabaseSealedPage({super.key, this.detail});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.restart_alt_rounded, size: 52),
                const SizedBox(height: 20),
                Text(
                  '数据已经换好了，重新打开 App 就能用。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '现在这个页面读到的还是换之前的数据，所以先停在这里。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: const Text('退出'),
                ),
                const SizedBox(height: 12),
                Text(
                  '重新打开后加载新数据',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 24),
                  SelectableText(
                    detail!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 封存态的统一异常文案（`databaseProvider` 抛出时用它）
const String kDatabaseSealedMessage = DatabaseSeal.message;
