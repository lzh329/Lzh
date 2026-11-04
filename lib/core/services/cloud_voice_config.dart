import 'dart:convert';

import 'package:fittrack/core/services/voice_presets.dart';
import 'package:fittrack/core/services/workout_coach.dart';

/// 三个音色通道
enum VoiceSource {
  /// 系统 TTS：零配置、离线可用，音质看手机
  system,

  /// Edge TTS：免费、无需 Key，非官方接口
  edge,

  /// MiniMax：付费、需 Key，音质最好
  minimax;

  static VoiceSource parse(String? raw) {
    switch (raw) {
      case 'minimax':
        return VoiceSource.minimax;
      case 'system':
        return VoiceSource.system;
      case 'edge':
        return VoiceSource.edge;
      default:
        // 未配置 / 脏值 → Edge（免费且音质明显好于系统 TTS），
        // 它失效时还会自动回落系统 TTS，所以拿它当默认最安全
        return VoiceSource.edge;
    }
  }

  String get wire => name;
}

/// 音色配置（存在 `user_settings.tts_config` 的一整块 JSON）。
///
/// 为什么要一个值对象而不是随手 map：
/// ① 解析必须**永不抛**（用户库里可能有半截 JSON / 旧版本字段）；
/// ② "这个通道现在能不能用"是复用的判断（设置页显示状态、训练页决定是否启用），
///    写在两处必然漂。
class CloudVoiceConfig {
  final VoiceSource source;

  final String? apiKey;
  final String? groupId;

  /// 国内 `https://api.minimax.chat`（默认）/ 国际 `https://api.minimax.io`
  final String? baseUrl;

  final String presetId;

  const CloudVoiceConfig({
    this.source = VoiceSource.edge,
    this.apiKey,
    this.groupId,
    this.baseUrl,
    this.presetId = VoicePresets.defaultPresetId,
  });

  /// 默认配置 = Edge 免费通道（新用户什么都不用配就能听到人声）
  static const defaults = CloudVoiceConfig();

  /// 显式选系统音色
  static const system = CloudVoiceConfig(source: VoiceSource.system);

  bool get isEdge => source == VoiceSource.edge;
  bool get isMinimax => source == VoiceSource.minimax;

  /// 这个通道现在是否可用：
  /// - Edge：恒可用（不需要 Key）；
  /// - MiniMax：必须填了 Key；
  /// - 系统：不经过"云端"，返回 false 表示"走系统"。
  bool get ready => switch (source) {
        VoiceSource.edge => true,
        VoiceSource.minimax => apiKey?.trim().isNotEmpty ?? false,
        VoiceSource.system => false,
      };

  VoicePreset get preset => VoicePresets.byId(presetId);

  /// 解析存储里的 JSON。**任何脏数据都回落默认配置**，绝不抛。
  static CloudVoiceConfig fromJsonString(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return defaults;
      final presetId = decoded['presetId'];
      return CloudVoiceConfig(
        source: VoiceSource.parse(decoded['provider'] as String?),
        apiKey: decoded['apiKey'] is String
            ? decoded['apiKey'] as String
            : null,
        groupId: decoded['groupId'] is String
            ? decoded['groupId'] as String
            : null,
        baseUrl: decoded['baseUrl'] is String
            ? decoded['baseUrl'] as String
            : null,
        presetId: presetId is String && presetId.isNotEmpty
            ? presetId
            : VoicePresets.defaultPresetId,
      );
    } catch (_) {
      return defaults; // 半截 JSON / 类型不对：当成没配
    }
  }

  /// 存回 JSON。写 `provider` 字段（沿用上一版的键名，老配置可平滑升级）
  String toJsonString() => jsonEncode({
        'provider': source.wire,
        if (apiKey != null) 'apiKey': apiKey,
        if (groupId != null) 'groupId': groupId,
        if (baseUrl != null) 'baseUrl': baseUrl,
        'presetId': presetId,
      });

  CloudVoiceConfig copyWith({
    VoiceSource? source,
    String? apiKey,
    String? groupId,
    String? baseUrl,
    String? presetId,
  }) =>
      CloudVoiceConfig(
        source: source ?? this.source,
        apiKey: apiKey ?? this.apiKey,
        groupId: groupId ?? this.groupId,
        baseUrl: baseUrl ?? this.baseUrl,
        presetId: presetId ?? this.presetId,
      );

  /// 把配置落到教练上。解析优先级就写在这一处，训练页与设置页共用：
  /// MiniMax（有 Key）→ Edge（无需 Key）→ 系统 TTS。
  void applyTo(WorkoutCoach coach) {
    final p = preset;
    if (source == VoiceSource.minimax) {
      final key = apiKey?.trim() ?? '';
      if (key.isEmpty) {
        // 选了付费但没填 Key：按约定回落系统 TTS（不偷偷换成别的音色 ——
        // 否则用户以为用的是 MiniMax，实际听到的是别人）
        coach.disableCloud();
        return;
      }
      coach.applyMinimaxConfig(
        apiKey: key,
        groupId: groupId,
        baseUrl: baseUrl,
        voiceId: p.voiceId,
        speed: p.speed,
        pitch: p.pitch,
      );
      return;
    }
    if (source == VoiceSource.edge) {
      coach.applyEdgeConfig(voiceId: p.edgeVoiceId, speed: p.speed, pitch: p.pitch);
      return;
    }
    coach.disableCloud();
  }
}
