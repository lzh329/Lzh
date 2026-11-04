/// 角色的"活体状态"（阶段 A 只做最小版：待机 / 训练中 / 休息中）。
///
/// 为什么放独立文件而不是塞进 `character_view.dart`：
/// ① 首页要按业务状态传它（训练页回来 → training），属于**跨组件契约**；
/// ② `character_view.dart` 已经贴着 300 行纪律，多一个枚举就顶破；
/// ③ 每个 mood 的动效参数集中在一处，调"有多活泼"不用翻两个文件。
enum CharacterMood {
  /// 待机（首页默认）
  idle,

  /// 训练中：浮动更快、幅度更大（有活力，但**不打扰**：不加速度、不闪）
  training,

  /// 休息中：更慢更轻（安静，别在用户躺下时还在蹦）
  resting,
}

/// 一个 mood 对应的动效参数。
///
/// 三个数字都刻意是小幅的：角色只占 195 逻辑像素高，超过 ±4% 的缩放就已经
/// "在动"了；再大就不是待机而是跳舞（首页会变得很吵）。
class CharacterMoodStyle {
  /// 呼吸一次的时间（越大越慢）
  final Duration breathCycle;

  /// 呼吸的缩放幅度（1.0 + 该值）
  final double breathScale;

  /// 随机小动作的幅度倍率（1.0 = 基准）
  final double gestureScale;

  const CharacterMoodStyle({
    required this.breathCycle,
    required this.breathScale,
    required this.gestureScale,
  });

  static const idle = CharacterMoodStyle(
    breathCycle: Duration(milliseconds: 2600),
    breathScale: 0.012,
    gestureScale: 1.0,
  );

  /// 训练中：快 40%、大 50%
  static const training = CharacterMoodStyle(
    breathCycle: Duration(milliseconds: 1600),
    breathScale: 0.018,
    gestureScale: 1.5,
  );

  /// 休息中：慢 40%、小 40%
  static const resting = CharacterMoodStyle(
    breathCycle: Duration(milliseconds: 3800),
    breathScale: 0.007,
    gestureScale: 0.6,
  );

  /// mood → 参数（唯一查表入口）
  static CharacterMoodStyle of(CharacterMood mood) => switch (mood) {
        CharacterMood.idle => idle,
        CharacterMood.training => training,
        CharacterMood.resting => resting,
      };
}
