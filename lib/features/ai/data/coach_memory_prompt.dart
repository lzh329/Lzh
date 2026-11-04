import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_service.dart';
import 'package:fittrack/features/ai/domain/coach_memory.dart';

/// 记忆抽取的提示词（独立文件，不碰对话用的四层结构）。
///
/// 这里只负责"让模型说清楚它听到了什么"，**不做校验** —— 白名单、quote 子串、
/// 长度、数字拦截全部在 `CoachMemoryPolicy` 里本地再做一遍。prompt 是"请对方
/// 配合"，本地校验才是"闸门"，两者缺一不可。
class CoachMemoryPrompt {
  CoachMemoryPrompt._();

  /// 白名单文案（与 `kMemoryCategories` 同源，不手抄一份）
  static String get _categoryList => kMemoryCategories
      .map((c) => '$c（${kMemoryCategoryLabels[c]}）')
      .join(' / ');

  static List<AiMessage> messages({
    required List<String> userTurns,
    required List<CoachMemory> existing,
  }) =>
      [
        AiMessage(role: 'system', content: systemPrompt()),
        AiMessage(role: 'user', content: userPrompt(userTurns, existing)),
      ];

  static String systemPrompt() {
    final buf = StringBuffer()
      ..writeln('你是一个「长期事实抽取器」。给你几轮用户原话，你只负责找出'
          '**值得长期记住**的情况，输出 JSON。')
      ..writeln()
      ..writeln('# 只记这 5 类，别的一律不记')
      ..writeln('- injury：伤病 / 疼痛 / 旧伤 / 手术史')
      ..writeln('- diet：忌口 / 过敏 / 不吃 / 只能吃')
      ..writeln('- schedule：作息 / 固定时间（几点下班、几点睡）')
      ..writeln('- agreement：用户答应过的事 / 双方的约定')
      ..writeln('- preference：明确的偏好 / 讨厌')
      ..writeln()
      ..writeln('# 绝对不能记（出现就跳过，不要输出）')
      ..writeln('1. 一次性信息：今天吃了什么、今天多少斤、今天累不累、今天练了多久')
      ..writeln('2. 一切数字型身体数据：体重、围度、热量目标（App 里已有真数据，'
          '重复存储必然和它对不上）')
      ..writeln('3. 隐私标识：真实姓名、电话、住址、单位、身份证号')
      ..writeln('4. 医疗结论：不要下诊断（"你有膝关节炎"这种）。'
          '用户说的"我右膝有旧伤"是 injury 事实，可以记；'
          '你自己推断出的病因，不许记')
      ..writeln()
      ..writeln('# 每条必须带 quote')
      ..writeln('quote 必须是用户原话里**逐字出现**的一段（≤60 字，不要改写、'
          '不要补标点、不要概括）。找不到能逐字引用的话，就不要输出这一条。')
      ..writeln()
      ..writeln('# topic 是覆盖用的短标签')
      ..writeln('topic 用 2~6 个字的稳定标签（如「右膝」「香菜」「晚上下班」「不吃主食」）。'
          '同一个人同一件事必须用同一个 topic —— 用户改口时靠它覆盖旧记录。'
          '拿不出 topic 就跳过。')
      ..writeln()
      ..writeln('# 用户改口了怎么办')
      ..writeln('如果用户明确说某件事已经好了 / 取消了 / 不算了，输出'
          '`"action":"forget"` 加那个 topic，不要输出一条相反的 remember。')
      ..writeln()
      ..writeln('# 输出格式')
      ..writeln('只输出 JSON 数组，不要代码块、不要解释。每项字段：')
      ..writeln('{"action":"remember|forget","category":"$_categoryList 之一",'
          '"topic":"...","content":"给用户看的一句话（≤60 字）",'
          '"quote":"用户原话片段","confidence":0.0~1.0}')
      ..writeln('一条都找不到就输出 []。最多 5 条，宁少勿多。');
    return buf.toString();
  }

  static String userPrompt(List<String> userTurns, List<CoachMemory> existing) {
    final buf = StringBuffer()..writeln('# 用户最近的原话（按时间顺序）');
    for (final t in userTurns) {
      buf.writeln('- ${t.replaceAll('\n', ' ')}');
    }
    buf
      ..writeln()
      ..writeln('# 已经记住的（同样的 topic 不要重复记，改口才输出）');
    if (existing.isEmpty) {
      buf.writeln('（还没有任何记忆）');
    } else {
      for (final m in existing) {
        buf.writeln('- ${m.category}/${m.topic}：${m.content}');
      }
    }
    buf
      ..writeln()
      ..writeln('请输出 JSON 数组。');
    return buf.toString();
  }

  /// 解析模型返回的 JSON（容忍 ```json 代码块与前后废话）。
  ///
  /// 任何不合法都返回空列表 —— 抽取失败是静默的（PRD 第八章）。
  static List<Map<String, dynamic>> parseCandidates(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'```(?:json)?', caseSensitive: false);
    if (text.contains('```')) {
      text = text.replaceAll(fence, '').replaceAll('```', '').trim();
    }
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map((e) {
        return e.map((k, v) => MapEntry(k.toString(), v));
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
