import 'package:drift/drift.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/settings/domain/repositories/user_settings_repository.dart';

class UserSettingsRepositoryImpl implements UserSettingsRepository {
  final AppDatabase _db;

  UserSettingsRepositoryImpl(this._db);

  @override
  Future<UserSettingsEntity?> get() async {
    final row =
        await (_db.select(_db.userSettings)..limit(1)).getSingleOrNull();
    return row != null ? _toEntity(row) : null;
  }

  @override
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
  }) async {
    final existing = await get();
    if (existing != null) {
      await (_db.update(_db.userSettings)
            ..where((t) => t.id.equals(existing.id)))
          .write(UserSettingsCompanion(
        heightCm: heightCm != null ? Value(heightCm) : const Value.absent(),
        targetWeightKg: targetWeightKg != null
            ? Value(targetWeightKg)
            : const Value.absent(),
        birthDate: birthDate != null ? Value(birthDate) : const Value.absent(),
        gender: gender != null ? Value(gender) : const Value.absent(),
        activityLevel:
            activityLevel != null ? Value(activityLevel) : const Value.absent(),
        pinCode: pinCode != null ? Value(pinCode) : const Value.absent(),
        lockEnabled:
            lockEnabled != null ? Value(lockEnabled) : const Value.absent(),
        speechRate:
            speechRate != null ? Value(speechRate) : const Value.absent(),
        speechPitch:
            speechPitch != null ? Value(speechPitch) : const Value.absent(),
        ttsVoice: ttsVoice != null ? Value(ttsVoice) : const Value.absent(),
        reminderEnabled: reminderEnabled != null
            ? Value(reminderEnabled)
            : const Value.absent(),
        reminderHour:
            reminderHour != null ? Value(reminderHour) : const Value.absent(),
        reminderMinute: reminderMinute != null
            ? Value(reminderMinute)
            : const Value.absent(),
        themeMode: themeMode != null ? Value(themeMode) : const Value.absent(),
        defaultTrainingSec: defaultTrainingSec != null
            ? Value(defaultTrainingSec)
            : const Value.absent(),
        defaultRestSec: defaultRestSec != null
            ? Value(defaultRestSec)
            : const Value.absent(),
        restShortSec:
            restShortSec != null ? Value(restShortSec) : const Value.absent(),
        restLongSec:
            restLongSec != null ? Value(restLongSec) : const Value.absent(),
        autoBackupEnabled: autoBackupEnabled != null
            ? Value(autoBackupEnabled)
            : const Value(true),
        aiApiKey: aiApiKey != null ? Value(aiApiKey) : const Value.absent(),
        aiStyle: aiStyle != null ? Value(aiStyle) : const Value.absent(),
        aiConstraints:
            aiConstraints != null ? Value(aiConstraints) : const Value.absent(),
        aiReplyLength:
            aiReplyLength != null ? Value(aiReplyLength) : const Value.absent(),
        aiTemperature:
            aiTemperature != null ? Value(aiTemperature) : const Value.absent(),
        aiPersonaCustom: aiPersonaCustom != null
            ? Value(aiPersonaCustom)
            : const Value.absent(),
        aiWebSearchEnabled: aiWebSearchEnabled != null
            ? Value(aiWebSearchEnabled)
            : const Value.absent(),
        dailyCalorieTarget: dailyCalorieTarget != null
            ? Value(dailyCalorieTarget)
            : const Value.absent(),
        proteinTargetG: proteinTargetG != null
            ? Value(proteinTargetG)
            : const Value.absent(),
        carbsTargetG:
            carbsTargetG != null ? Value(carbsTargetG) : const Value.absent(),
        fatTargetG:
            fatTargetG != null ? Value(fatTargetG) : const Value.absent(),
      ));
      return _rereadOrThrow();
    } else {
      await _db.into(_db.userSettings).insert(UserSettingsCompanion(
            heightCm: heightCm != null ? Value(heightCm) : const Value.absent(),
            targetWeightKg: targetWeightKg != null
                ? Value(targetWeightKg)
                : const Value.absent(),
            birthDate:
                birthDate != null ? Value(birthDate) : const Value.absent(),
            gender: gender != null ? Value(gender) : const Value.absent(),
            activityLevel: activityLevel != null
                ? Value(activityLevel)
                : const Value.absent(),
            pinCode: pinCode != null ? Value(pinCode) : const Value.absent(),
            lockEnabled:
                lockEnabled != null ? Value(lockEnabled) : const Value(false),
            speechRate:
                speechRate != null ? Value(speechRate) : const Value.absent(),
            speechPitch:
                speechPitch != null ? Value(speechPitch) : const Value.absent(),
            ttsVoice: ttsVoice != null ? Value(ttsVoice) : const Value.absent(),
            reminderEnabled: reminderEnabled != null
                ? Value(reminderEnabled)
                : const Value(false),
            reminderHour: reminderHour != null
                ? Value(reminderHour)
                : const Value.absent(),
            reminderMinute: reminderMinute != null
                ? Value(reminderMinute)
                : const Value.absent(),
            themeMode:
                themeMode != null ? Value(themeMode) : const Value.absent(),
            defaultTrainingSec: defaultTrainingSec != null
                ? Value(defaultTrainingSec)
                : const Value.absent(),
            defaultRestSec: defaultRestSec != null
                ? Value(defaultRestSec)
                : const Value.absent(),
            restShortSec: restShortSec != null
                ? Value(restShortSec)
                : const Value.absent(),
            restLongSec:
                restLongSec != null ? Value(restLongSec) : const Value.absent(),
            autoBackupEnabled: autoBackupEnabled != null
                ? Value(autoBackupEnabled)
                : const Value.absent(),
            aiApiKey: aiApiKey != null ? Value(aiApiKey) : const Value.absent(),
            aiStyle: aiStyle != null ? Value(aiStyle) : const Value.absent(),
            aiConstraints: aiConstraints != null
                ? Value(aiConstraints)
                : const Value.absent(),
            aiReplyLength: aiReplyLength != null
                ? Value(aiReplyLength)
                : const Value.absent(),
            aiTemperature: aiTemperature != null
                ? Value(aiTemperature)
                : const Value.absent(),
            aiPersonaCustom: aiPersonaCustom != null
                ? Value(aiPersonaCustom)
                : const Value.absent(),
            // 新建记录时未指定就显式落 true（与建表默认值一致，别依赖 absent）
            aiWebSearchEnabled: aiWebSearchEnabled != null
                ? Value(aiWebSearchEnabled)
                : const Value(true),
            dailyCalorieTarget: dailyCalorieTarget != null
                ? Value(dailyCalorieTarget)
                : const Value.absent(),
            proteinTargetG: proteinTargetG != null
                ? Value(proteinTargetG)
                : const Value.absent(),
            carbsTargetG: carbsTargetG != null
                ? Value(carbsTargetG)
                : const Value.absent(),
            fatTargetG:
                fatTargetG != null ? Value(fatTargetG) : const Value.absent(),
          ));
      return _rereadOrThrow();
    }
  }

  // ── 误报计数（v21 · user_settings.ai_health_override_count）──
  //
  // 只在这里碰这一列：自增走单条原子 UPDATE，绝不先读后写 —— 连续撤销两次
  // （用户点得快 / 两个入口并发）时 read-modify-write 会丢一次计数。
  // COALESCE 是保险：老库加列时若写入过 NULL，+1 不会变成 NULL。

  @override
  Future<void> incrementAiHealthOverrideCount() async {
    final id = await _rowIdOrCreate();
    await _db.customStatement(
      'UPDATE user_settings SET ai_health_override_count = '
      'COALESCE(ai_health_override_count, 0) + 1 WHERE id = ?',
      <Object?>[id],
    );
  }

  @override
  Future<void> resetAiHealthOverrideCount() async {
    final existing = await get();
    if (existing == null) return; // 没有设置行 = 没有记过，本就是 0，不必建行
    await _db.customStatement(
      'UPDATE user_settings SET ai_health_override_count = 0 WHERE id = ?',
      <Object?>[existing.id],
    );
  }

  /// 设置行的 id；还没有行就先建一行（计数必须有落点）。
  Future<int> _rowIdOrCreate() async {
    final existing = await get();
    return existing?.id ?? (await save()).id;
  }

  /// 写入后回读最新记录
  ///
  /// 用显式异常替代原来的 `!` 空断言：极端情况（并发删除 / 写入被丢弃）下
  /// 抛出可读错误，由上层 try/catch 兜底，避免空断言导致难以定位的崩溃。
  Future<UserSettingsEntity> _rereadOrThrow() async {
    final saved = await get();
    if (saved == null) {
      throw StateError('UserSettings 写入后回读为空');
    }
    return saved;
  }

  UserSettingsEntity _toEntity(UserSetting row) => UserSettingsEntity(
        id: row.id,
        heightCm: row.heightCm,
        targetWeightKg: row.targetWeightKg,
        birthDate: row.birthDate,
        gender: row.gender,
        activityLevel: row.activityLevel,
        pinCode: row.pinCode,
        lockEnabled: row.lockEnabled,
        speechRate: row.speechRate,
        speechPitch: row.speechPitch,
        ttsVoice: row.ttsVoice,
        reminderEnabled: row.reminderEnabled,
        reminderHour: row.reminderHour,
        reminderMinute: row.reminderMinute,
        themeMode: row.themeMode,
        defaultTrainingSec: row.defaultTrainingSec,
        defaultRestSec: row.defaultRestSec,
        restShortSec: row.restShortSec,
        restLongSec: row.restLongSec,
        autoBackupEnabled: row.autoBackupEnabled,
        aiApiKey: row.aiApiKey,
        aiStyle: row.aiStyle,
        aiConstraints: row.aiConstraints,
        aiReplyLength: row.aiReplyLength,
        aiTemperature: row.aiTemperature,
        aiPersonaCustom: row.aiPersonaCustom,
        aiWebSearchEnabled: row.aiWebSearchEnabled,
        dailyCalorieTarget: row.dailyCalorieTarget,
        proteinTargetG: row.proteinTargetG,
        carbsTargetG: row.carbsTargetG,
        fatTargetG: row.fatTargetG,
        aiHealthOverrideCount: row.aiHealthOverrideCount,
      );
}
