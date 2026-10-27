class UserSettingsEntity {
  final int id;
  final double? heightCm;
  final double? targetWeightKg;
  final DateTime? birthDate;
  final String? gender; // male / female
  final String?
      activityLevel; // sedentary / light / moderate / active / very_active
  final String? pinCode; // 4位数字PIN
  final bool lockEnabled;
  final double? speechRate; // 0.0 ~ 1.0
  final double? speechPitch; // 0.5 ~ 2.0
  final String? ttsVoice; // 系统 TTS 音色标识
  final bool reminderEnabled;
  final int? reminderHour;
  final int? reminderMinute;
  final String? themeMode;
  final int? defaultTrainingSec;
  final int? defaultRestSec;

  /// 循环模式：动作间休息（秒）
  final int? restShortSec;

  /// 循环模式：轮间休息（秒）
  final int? restLongSec;

  /// 每周自动备份数据库（默认开）
  final bool autoBackupEnabled;

  /// AI 教练：智谱 API Key（与 --dart-define 互补）
  final String? aiApiKey;

  /// AI 教练风格：doubao（豆包感，默认）/ guga（嘎式）/ gentle（温柔）/ strict（严厉）
  final String? aiStyle;

  /// 用户自定义约束（JSON 数组字符串，每条一句规则）
  final String? aiConstraints;

  /// 回复长度：short / medium / long
  final String? aiReplyLength;

  /// 自由度 temperature（0.3 ~ 1.0）
  final double? aiTemperature;

  /// 用户自定义人设文案（多行，只替换「角色」段；null / 空串 = 用风格默认）
  final String? aiPersonaCustom;
  // 饮食目标
  final int? dailyCalorieTarget;
  final double? proteinTargetG;
  final double? carbsTargetG;
  final double? fatTargetG;

  const UserSettingsEntity({
    required this.id,
    this.heightCm,
    this.targetWeightKg,
    this.birthDate,
    this.gender,
    this.activityLevel,
    this.pinCode,
    this.lockEnabled = false,
    this.speechRate,
    this.speechPitch,
    this.ttsVoice,
    this.reminderEnabled = false,
    this.reminderHour,
    this.reminderMinute,
    this.themeMode,
    this.defaultTrainingSec,
    this.defaultRestSec,
    this.restShortSec,
    this.restLongSec,
    this.autoBackupEnabled = true,
    this.aiApiKey,
    this.aiStyle,
    this.aiConstraints,
    this.aiReplyLength,
    this.aiTemperature,
    this.aiPersonaCustom,
    this.dailyCalorieTarget,
    this.proteinTargetG,
    this.carbsTargetG,
    this.fatTargetG,
  });

  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    int age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age--;
    }
    return age;
  }

  /// BMI = 体重(kg) / 身高(m)²，身高为空时返回 null
  double? bmi(double weightKg) {
    if (heightCm == null || heightCm! <= 0) return null;
    final heightM = heightCm! / 100;
    return weightKg / (heightM * heightM);
  }

  /// BMR 基础代谢率 (Mifflin-St Jeor)
  double? bmr() {
    if (heightCm == null ||
        heightCm! <= 0 ||
        birthDate == null ||
        gender == null) {
      return null;
    }
    final a = age;
    if (a == null) return null;
    if (gender == 'male') {
      return 10 * (targetWeightKg ?? 70) + 6.25 * heightCm! - 5 * a + 5;
    }
    return 10 * (targetWeightKg ?? 60) + 6.25 * heightCm! - 5 * a - 161;
  }

  /// TDEE 每日总消耗
  double? tdee() {
    final b = bmr();
    if (b == null) return null;
    switch (activityLevel) {
      case 'sedentary':
        return b * 1.2;
      case 'light':
        return b * 1.375;
      case 'moderate':
        return b * 1.55;
      case 'active':
        return b * 1.725;
      case 'very_active':
        return b * 1.9;
      default:
        return b * 1.2;
    }
  }

  /// BMI 等级
  static String bmiLevel(double bmi) {
    if (bmi < 18.5) return 'underweight';
    if (bmi < 24.0) return 'normal';
    if (bmi < 28.0) return 'overweight';
    return 'obese';
  }

  static const bmiLevelLabels = {
    'underweight': '偏瘦',
    'normal': '正常',
    'overweight': '微胖',
    'obese': '肥胖',
  };

  static const activityLevelLabels = {
    'sedentary': '久坐不动',
    'light': '轻度活动 (1-2天/周)',
    'moderate': '中度活动 (3-5天/周)',
    'active': '高度活跃 (6-7天/周)',
    'very_active': '极高活跃 (每天高强度)',
  };

  static const genderLabels = {
    'male': '男',
    'female': '女',
  };
}
