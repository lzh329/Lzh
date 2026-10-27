/// 工具调用不合法（参数越界 / 未知工具）——由 App 侧拦截，模型无法绕过
class AiToolException implements Exception {
  final String message;
  const AiToolException(this.message);

  @override
  String toString() => message;
}
