import 'package:fittrack/core/services/character_catalog.dart';

/// prompt 里的「陪伴角色」那一行（C14）。
///
/// 为什么单独一个文件：`ai_prompt_builder.dart` 已经 308 行（超 300 纪律）。
/// 把这一行的措辞和「怎么拼」拆出来，builder 只多一次调用、不增加行数债；
/// 同时这一行有独立的测试（`character_prompt_test.dart`），
/// 改文案时不用在一个 300 行的 prompt 构建器里找。
///
/// 措辞三件事（顺序即优先级）：
/// 1. 告诉模型**现在**陪着他的是谁（否则糯糯面前它会说"你的咕嘎"）；
/// 2. 明确"提到它时用这个名字"（不写这句，模型会顺手用惯了的旧名）；
/// 3. 明确"不要自称这个名字" —— 角色是用户选的形象，教练是产品人格，
///    两者解耦才不会出现"换了糯糯，AI 开始说'我是糯糯'"（决策 7）。
abstract final class CharacterPromptLine {
  static String of(CharacterRenderSpec spec) =>
      '【陪伴角色】${spec.name}。提到它时用这个名字，不要叫咕嘎；不要自称这个名字';
}
