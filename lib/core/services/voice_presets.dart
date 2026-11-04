/// 音色的 5 个预设。
///
/// **一个预设两套音色 id**：`edgeVoiceId`（Edge TTS，免费）与 `voiceId`（MiniMax，
/// 付费）。同一档"声音性格"在两个供应商各有一个最接近的对应音色 ——
/// 这样用户换供应商时**不用重选预设**，听感不会跳。
///
/// 为什么是"预设"而不是让用户选 voice_id：
/// MiniMax 有几十个 `voice_id`（`Chinese (Mandarin)_Warm_Bestie` 这种），
/// 普通用户根本不知道该选哪个、也听不出差别。产品要的是"一键换个感觉" ——
/// 所以这里挑 5 个覆盖常见诉求的声音，并用**人的语言**命名（温柔女声 / 元气少女…）。
///
/// 语速/音调是**预设的一部分**（不是全局设置）：把「严厉教练」调到 0.95 语速
/// 就不严厉了，所以每个预设自带一套参数，切预设即为切参数。
class VoicePreset {
  final String id;
  final String name;
  final String desc;

  /// MiniMax 的 voice_id（付费通道）
  final String voiceId;

  /// Edge TTS 的 voice name（免费通道，如 `zh-CN-XiaoxiaoNeural`）
  final String edgeVoiceId;

  /// 0.5~2.0（MiniMax 允许范围；这里都落在 0.95~1.1 的自然区间）
  final double speed;

  /// -12~12（int，MiniMax 要求整数）
  final int pitch;

  final String emoji;

  const VoicePreset({
    required this.id,
    required this.name,
    required this.desc,
    required this.voiceId,
    required this.edgeVoiceId,
    required this.speed,
    required this.pitch,
    required this.emoji,
  });
}

class VoicePresets {
  VoicePresets._();

  static const all = <VoicePreset>[
    VoicePreset(
      id: 'gentle_female',
      name: '温柔女声',
      desc: '像朋友在旁边轻声提醒，适合拉伸和恢复日',
      voiceId: 'Chinese (Mandarin)_Warm_Bestie',
      edgeVoiceId: 'zh-CN-XiaoxiaoNeural',
      speed: 0.95,
      pitch: 0,
      emoji: '🌸',
    ),
    VoicePreset(
      id: 'energetic_girl',
      name: '元气少女',
      desc: '节奏偏快、语气上扬，适合 HIIT 和短间歇',
      voiceId: 'female-shaonv',
      edgeVoiceId: 'zh-CN-XiaoyiNeural',
      speed: 1.05,
      pitch: 1,
      emoji: '⚡',
    ),
    VoicePreset(
      id: 'mature_female',
      name: '御姐',
      desc: '沉稳一点的女声，不催不哄，念数字很清楚',
      voiceId: 'female-yujie',
      edgeVoiceId: 'zh-CN-XiaochenNeural',
      speed: 1.0,
      pitch: -1,
      emoji: '🌙',
    ),
    VoicePreset(
      id: 'calm_male',
      name: '沉稳男声',
      desc: '低音、慢半拍，适合力量训练时的长组间休息',
      voiceId: 'male-qn-qingse',
      edgeVoiceId: 'zh-CN-YunyangNeural',
      speed: 1.0,
      pitch: -2,
      emoji: '🎧',
    ),
    VoicePreset(
      id: 'strict_coach',
      name: '严厉教练',
      desc: '短促有力，倒计时会把你从地上拽起来',
      voiceId: 'male-qn-jingying',
      edgeVoiceId: 'zh-CN-YunjianNeural',
      speed: 1.1,
      pitch: -3,
      emoji: '🔥',
    ),
  ];

  /// 找不到（null / 脏值 / 老配置里的旧 id）一律回落**第一个**：
  /// 宁可用默认音色，也不要因为一个字符串让语音整段失效。
  static VoicePreset byId(String? id) {
    if (id == null || id.isEmpty) return all.first;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return all.first;
  }

  static const defaultPresetId = 'gentle_female';
}
