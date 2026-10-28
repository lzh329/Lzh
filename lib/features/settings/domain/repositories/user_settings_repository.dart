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
    String? aiStyle,
    String? aiConstraints,
    String? aiReplyLength,
    double? aiTemperature,
    String? aiPersonaCustom,
    bool? aiWebSearchEnabled,
    int? dailyCalorieTarget,
    double? proteinTargetG,
    double? carbsTargetG,
    double? fatTargetG,
  });

  /// 误报计数 +1（原子自增，不做 read-modify-write —— 连续撤销会丢计数）。
  ///
  /// 对应 `user_settings.ai_health_override_count`；没有设置行时先建行再自增。
  Future<void> incrementAiHealthOverrideCount();

  /// 误报计数清零（设置页「重置 AI 健康建议」手动兜底；本期不自动衰减）。
  Future<void> resetAiHealthOverrideCount();
}
