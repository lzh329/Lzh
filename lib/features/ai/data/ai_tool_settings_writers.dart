import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 设置类写操作：set_target_weight / update_profile / set_diet_target / set_reminder
class AiToolSettingsWriters extends AiToolHandler {
  const AiToolSettingsWriters(super.repos);

  /// 每日称重提醒的通知 id（与设置页 100~106 的排期区分开，避免被 cancelAll 之外的逻辑覆盖）
  static const weighInReminderId = 9001;

  /// 提醒时间缺省值 09:00
  static const defaultHour = 9;
  static const defaultMinute = 0;

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.setTargetWeight,
        AiToolSpecs.updateProfile,
        AiToolSpecs.setDietTarget,
        AiToolSpecs.setReminder,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.setTargetWeight:
        final jin = AiToolArgs.targetWeightKg(call.arguments) * 2;
        return AiToolPreview(
          call: call,
          label: '设置目标体重',
          detail: '目标体重 ${AiToolFormat.jin(jin)} 斤',
          needsConfirm: true,
        );

      case AiToolSpecs.updateProfile:
        final input = AiToolArgs.profile(call.arguments);
        return AiToolPreview(
          call: call,
          label: '更新身体信息',
          detail: input.label,
          needsConfirm: true,
        );

      case AiToolSpecs.setDietTarget:
        final input = AiToolArgs.dietTarget(call.arguments);
        return AiToolPreview(
          call: call,
          label: '设置饮食目标',
          detail: input.label,
          needsConfirm: true,
        );

      case AiToolSpecs.setReminder:
        final args = call.arguments;
        final enabled = AiToolArgs.boolArg(args, 'enabled', '提醒');
        final hour = AiToolArgs.optionalHour(args) ?? defaultHour;
        final minute = AiToolArgs.optionalMinute(args) ?? defaultMinute;
        return AiToolPreview(
          call: call,
          label: enabled ? '开启每日提醒' : '关闭每日提醒',
          detail: enabled ? '每天 ${_hhmm(hour, minute)} 提醒称重' : '关闭每日提醒',
          needsConfirm: true,
        );

      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.setTargetWeight:
        return _setTargetWeight(call);
      case AiToolSpecs.updateProfile:
        return _updateProfile(call);
      case AiToolSpecs.setDietTarget:
        return _setDietTarget(call);
      case AiToolSpecs.setReminder:
        return _setReminder(call);
      default:
        unsupported(call);
    }
  }

  Future<String> _setTargetWeight(AiToolCall call) async {
    final weightKg = AiToolArgs.targetWeightKg(call.arguments);
    await repos.settings.save(targetWeightKg: weightKg);
    return jsonEncode({
      'ok': true,
      'target_jin': double.parse(AiToolFormat.jinFromKg(weightKg)),
    });
  }

  Future<String> _updateProfile(AiToolCall call) async {
    final input = AiToolArgs.profile(call.arguments);
    await repos.settings.save(
      heightCm: input.heightCm,
      gender: input.gender,
      birthDate:
          input.birthYear == null ? null : DateTime(input.birthYear!, 1, 1),
    );
    return jsonEncode({
      'ok': true,
      'height_cm': input.heightCm,
      'gender': input.gender,
      'birth_year': input.birthYear,
    });
  }

  Future<String> _setDietTarget(AiToolCall call) async {
    final input = AiToolArgs.dietTarget(call.arguments);
    await repos.settings.save(
      dailyCalorieTarget: input.calories,
      proteinTargetG: input.proteinG,
      carbsTargetG: input.carbsG,
      fatTargetG: input.fatG,
    );
    return jsonEncode({
      'ok': true,
      'calories': input.calories,
      'protein_g': input.proteinG,
      'carbs_g': input.carbsG,
      'fat_g': input.fatG,
    });
  }

  Future<String> _setReminder(AiToolCall call) async {
    final args = call.arguments;
    final enabled = AiToolArgs.boolArg(args, 'enabled', '提醒');
    final hour = AiToolArgs.optionalHour(args) ?? defaultHour;
    final minute = AiToolArgs.optionalMinute(args) ?? defaultMinute;
    await repos.settings.save(
      reminderEnabled: enabled,
      reminderHour: hour,
      reminderMinute: minute,
    );
    await _applyReminder(enabled: enabled, hour: hour, minute: minute);
    return jsonEncode({
      'ok': true,
      'enabled': enabled,
      'hour': hour,
      'minute': minute,
    });
  }

  /// 同步系统通知：开启则排期，关闭则取消
  ///
  /// 通知权限被拒 / 平台不支持时静默失败 —— 设置本身已经写库，不影响聊天继续。
  Future<void> _applyReminder({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    final ns = NotificationService();
    try {
      if (enabled) {
        await ns.scheduleDailyWeighInReminder(
          id: weighInReminderId,
          hour: hour,
          minute: minute,
        );
      } else {
        await ns.cancelById(weighInReminderId);
      }
    } catch (e) {
      debugPrint('AI 提醒设置失败: $e');
    }
  }

  static String _hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
