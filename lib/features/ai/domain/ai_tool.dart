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

/// 工具调用的人为上限（只管"防死循环"，不管安全）
class AiToolLimits {
  AiToolLimits._();

  /// 一轮对话里最多允许的工具调用次数
  ///
  /// 12 = 一次建模板（1）+ 批量补建动作（最多 10）+ 余量，覆盖正常上限；
  /// **写操作的确认闸门没有放宽**：每个写工具依旧逐次弹确认卡，
  /// 这里的次数限制只防止模型自己绕圈刷工具。
  static const maxCallsPerRound = 12;

  /// 超限时给**用户**看的话（必须说清"为什么停"和"下一步怎么做"）
  ///
  /// 之前超限只把 isStreaming 置 false 就 return —— 用户看到的是
  /// "不转圈也不回话"，像卡死了。30 个动作的模板很容易触发。
  static String userLimitNotice(int executed) =>
      '这轮操作有点多（已经执行 $executed 次），我先停一下。'
      '你说「继续」，我接着做。';

  /// 超过上限时给**模型**的回执（已告知用户，别重复解释）
  static const overLimitMessage = '一次对话里操作次数过多，请分两步说（已告知用户）';
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
