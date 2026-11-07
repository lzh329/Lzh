import 'package:fittrack/core/services/character_catalog.dart';

import '../entities/user_settings_entity.dart';

abstract class UserSettingsRepository {
  Future<UserSettingsEntity?> get();
  Future<UserSettingsEntity> save({
    double? heightCm,
    double? targetWeightKg,
    DateTime? birthDate,
    String? gender,
    String? activityLevel,
    String? pinCode,
    bool? lockEnabled,
    double? speechRate,
    double? speechPitch,
    String? ttsVoice,
    String? ttsConfig,
    bool? reminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    String? themeMode,
    int? defaultTrainingSec,
    int? defaultRestSec,
    int? restShortSec,
    int? restLongSec,
    bool? autoBackupEnabled,
    String? aiApiKey,
    String? aiProviderId,
    String? aiStyle,
    String? aiConstraints,
    String? aiReplyLength,
    double? aiTemperature,
    String? aiPersonaCustom,
    bool? aiWebSearchEnabled,
    String? countdownVoiceMode,
    int? dailyCalorieTarget,
    double? proteinTargetG,
    double? carbsTargetG,
    double? fatTargetG,
  });

  /// 关闭隐私锁并清空 PIN（"忘记 PIN" 的唯一出路）。
  ///
  /// 必须走显式 SQL：`save(pinCode: null)` 的语义是「不改」，用它清不掉 PIN。
  /// 这一步只动锁，不动任何业务数据 —— 用户被锁在门外时，数据完好比什么都重要。
  Future<void> clearLock();

  /// 误报计数 +1（原子自增，不做 read-modify-write —— 连续撤销会丢计数）。
  ///
  /// 对应 `user_settings.ai_health_override_count`；没有设置行时先建行再自增。
  /// 设置昵称；传 null = **清除**（写回 NULL，不是空串）
  Future<void> saveNickname(String? nickname);

  /// 设置头像路径；传 null = 清除
  Future<void> saveAvatarPath(String? avatarPath);

  Future<void> incrementAiHealthOverrideCount();

  /// 误报计数清零（设置页「重置 AI 健康建议」手动兜底；本期不自动衰减）。
  Future<void> resetAiHealthOverrideCount();

  /// v24：教练主动性两开关（记忆 / 主动消息）。
  ///
  /// 不并进 [save]：那是"改身体信息 / 提醒"那条路径，一次传 30 多个可选参数；
  /// 再塞两个进去要在 update / insert 两处各写一遍 `Value(...)`，容易漏。
  /// 这里**没传 = 不改**，不会把另一个开关冲掉。
  Future<void> saveCoachEngagement({
    bool? memoryEnabled,
    bool? proactiveEnabled,
  });

  /// v25：切换角色（形象页唯一的写入口）。
  ///
  /// 入参是**枚举**而不是 String，这是 C4 的类型级防线：
  /// 「把 DB 里的脏值原样写回去」在这里根本不成立 —— 读路径永远不会触发写。
  ///
  /// 没有设置行时先建行再写（新用户还没填过任何东西也能换形象）。
  Future<void> saveCharacterId(CharacterId id);
}
