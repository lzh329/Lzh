import 'dart:convert';

export 'ai_tool_args.dart';
export 'ai_tool_exception.dart';
export 'ai_tool_inputs.dart';
export 'ai_tool_specs.dart';

/// 模型请求的一次工具调用
class AiToolCall {
  final String id;
  final String name;
  final String argumentsJson; // 模型返回的 JSON 字符串（可能不完整/非法）

  const AiToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  Map<String, dynamic> get arguments {
    try {
      final v = jsonDecode(argumentsJson);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// 工具调用的执行预览（用于确认卡片）
class AiToolPreview {
  final AiToolCall call;
  final String label; // 记录体重
  final String detail; // 161.0 斤 · 今天
  final bool needsConfirm; // 写操作需确认，查询类直接执行

  /// 危险操作（删除类）：确认卡用警示色，按钮文案为「确认删除」
  final bool isDestructive;

  const AiToolPreview({
    required this.call,
    required this.label,
    required this.detail,
    required this.needsConfirm,
    this.isDestructive = false,
  });
}

/// 统一的展示格式化（只做字符串，不做校验）
class AiToolFormat {
  AiToolFormat._();

  /// 80.0 → "80"，80.5 → "80.5"
  static String num(double v) {
    final rounded = v.roundToDouble();
    return v == rounded ? rounded.round().toString() : v.toStringAsFixed(1);
  }

  /// 公斤 → 斤的展示（保留一位小数）
  static String jinFromKg(double kg) => (kg * 2).toStringAsFixed(1);

  /// 斤的展示（保留一位小数）
  static String jin(double jin) => jin.toStringAsFixed(1);

  /// 日期 → 2025-10-26
  static String ymd(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 当天 0 点
  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
}
