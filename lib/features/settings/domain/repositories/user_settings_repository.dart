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
    int? dailyCalorieTarget,
    double? proteinTargetG,
    double? carbsTargetG,
    double? fatTargetG,
  });
}
