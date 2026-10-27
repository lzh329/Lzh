import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/features/ai/data/ai_tool_admin_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/data/ai_tool_library_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_readers.dart';
import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/data/ai_tool_settings_writers.dart';
import 'package:fittrack/features/ai/data/ai_tool_web_readers.dart';
import 'package:fittrack/features/ai/data/ai_tool_workout_launcher.dart';
import 'package:fittrack/features/ai/data/ai_tool_writers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 工具执行器 —— 模型只能提交"意图"，真正写库在这里，且经过白名单 + 参数校验
///
/// 分派给七组处理器：只读查询、联网搜索/读网页、记录类、设置类、管理类、
/// 动作库/模板类、训练启动类。新增工具只要加一个处理器实现并在 [_handlers]
/// 注册，不用改这里的分派逻辑。
class AiToolExecutor {
  final AiToolRepos _repos;

  late final List<AiToolHandler> _handlers = [
    AiToolReaders(_repos),
    AiToolWebReaders(_repos),
    AiToolWriters(_repos),
    AiToolSettingsWriters(_repos),
    AiToolAdminWriters(_repos),
    AiToolLibraryWriters(_repos),
    AiToolWorkoutLauncher(_repos),
  ];

  AiToolExecutor({required AiToolRepos repos}) : _repos = repos;

  /// 从 providers 构建
  factory AiToolExecutor.fromRef(Ref ref) =>
      AiToolExecutor(repos: AiToolRepos.fromRef(ref));

  /// 校验并生成确认卡内容（越界直接抛 AiToolException）
  Future<AiToolPreview> preview(AiToolCall call) =>
      _handlerFor(call).preview(call);

  /// 执行工具，返回给模型的 JSON 结果
  Future<String> execute(AiToolCall call) => _handlerFor(call).execute(call);

  AiToolHandler _handlerFor(AiToolCall call) {
    for (final handler in _handlers) {
      if (handler.supports(call.name)) return handler;
    }
    throw AiToolException('不支持的操作：${call.name}');
  }
}
