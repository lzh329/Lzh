import 'package:fittrack/features/ai/data/ai_tool_repos.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 一类工具（记录 / 设置 / 管理 / 只读）的处理器
///
/// 每个实现只负责自己那组工具：
/// - [preview] 生成确认卡文案（不写库，危险操作允许查库统计）
/// - [execute] 真正写库 / 查询，返回给模型的 JSON 字符串
abstract class AiToolHandler {
  const AiToolHandler(this.repos);

  final AiToolRepos repos;

  /// 本处理器负责的工具名（白名单）
  Set<String> get toolNames;

  bool supports(String name) => toolNames.contains(name);

  Future<AiToolPreview> preview(AiToolCall call);

  Future<String> execute(AiToolCall call);

  /// 白名单外的调用一律拦截，模型无法绕过
  Never unsupported(AiToolCall call) =>
      throw AiToolException('不支持的操作：${call.name}');
}
