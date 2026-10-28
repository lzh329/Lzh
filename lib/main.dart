import 'package:flutter/material.dart';

import 'core/bootstrap.dart';

/// 启动入口。全部逻辑在 [buildStartupRoot] 里（可注入、可单测），
/// 这里只保留「跑起来」这一件事，避免以后再有人往启动路径里塞 `await`。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await buildStartupRoot());
}
