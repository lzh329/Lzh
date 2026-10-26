import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';
import 'package:fittrack/features/water/data/water_repository_impl.dart'
    show WaterRepository;
import 'package:fittrack/features/workout/domain/repositories/workout_repository.dart';

/// 工具执行器 —— 模型只能提交"意图"，真正写库在这里，且经过白名单 + 参数校验
class AiToolExecutor {
  final BodyMetricRepository _bodyRepo;
  final WaterRepository _waterRepo;
  final WorkoutRepository _workoutRepo;
  final DietRepository _dietRepo;

  AiToolExecutor({
    required BodyMetricRepository bodyRepo,
    required WaterRepository waterRepo,
    required WorkoutRepository workoutRepo,
    required DietRepository dietRepo,
  })  : _bodyRepo = bodyRepo,
        _waterRepo = waterRepo,
        _workoutRepo = workoutRepo,
        _dietRepo = dietRepo;

  /// 从 providers 构建
  factory AiToolExecutor.fromRef(Ref ref) => AiToolExecutor(
        bodyRepo: ref.read(bodyMetricRepoProvider),
        waterRepo: ref.read(waterRepoProvider),
        workoutRepo: ref.read(workoutRepoProvider),
        dietRepo: ref.read(dietRepoProvider),
      );

  /// 校验并生成确认卡内容（越界直接抛 AiToolException）
  AiToolPreview preview(AiToolCall call) {
    switch (call.name) {
      case AiToolSpecs.logWeight:
        final args = call.arguments;
        final jin = AiToolArgs.weightJin(args);
        final date = AiToolArgs.date(args);
        return AiToolPreview(
          call: call,
          label: '记录体重',
          detail: '${jin.toStringAsFixed(1)} 斤 · ${AiToolArgs.dateLabel(date)}',
          needsConfirm: true,
        );
      case AiToolSpecs.logWater:
        final cups = AiToolArgs.cups(call.arguments);
        return AiToolPreview(
          call: call,
          label: '记录饮水',
          detail: '今天共 $cups 杯（约 ${cups * 200} ml）',
          needsConfirm: true,
        );
      case AiToolSpecs.queryStats:
        final range = AiToolArgs.range(call.arguments);
        return AiToolPreview(
          call: call,
          label: '查询统计',
          detail: range == 'week' ? '本周' : (range == 'month' ? '本月' : '全部'),
          needsConfirm: false,
        );
      default:
        throw AiToolException('不支持的操作：${call.name}');
    }
  }

  /// 执行工具，返回给模型的 JSON 结果
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.logWeight:
        final args = call.arguments;
        final weightKg = AiToolArgs.weightKg(args);
        final date = AiToolArgs.date(args);
        await _bodyRepo.create(date: date, weightKg: weightKg, note: 'AI 教练记录');
        return jsonEncode({
          'ok': true,
          'saved': {
            'weight_jin': (weightKg * 2).toStringAsFixed(1),
            'date': _ymd(date),
          },
        });

      case AiToolSpecs.logWater:
        final cups = AiToolArgs.cups(call.arguments);
        await _waterRepo.setTodayCups(cups);
        return jsonEncode({'ok': true, 'cups': cups, 'ml': cups * 200});

      case AiToolSpecs.queryStats:
        return _queryStats(AiToolArgs.range(call.arguments));

      default:
        throw AiToolException('不支持的操作：${call.name}');
    }
  }

  Future<String> _queryStats(String range) async {
    final now = DateTime.now();
    DateTime from;
    switch (range) {
      case 'month':
        from = DateTime(now.year, now.month, 1);
      case 'all':
        from = DateTime(2000);
      default:
        from = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    }

    final metrics = await _bodyRepo.getAll();
    final sorted = [...metrics]..sort((a, b) => a.date.compareTo(b.date));
    final workouts = await _workoutRepo.getAll();
    final weekWorkouts =
        workouts.where((w) => !w.date.isBefore(from)).toList();
    final cups = await _waterRepo.getTodayCups();
    final calories = await _dietRepo.getDailyCalories(now);

    return jsonEncode({
      'range': range,
      'weight': {
        'latest_jin': sorted.isEmpty
            ? null
            : double.parse((sorted.last.weightKg * 2).toStringAsFixed(1)),
        'first_jin': sorted.isEmpty
            ? null
            : double.parse((sorted.first.weightKg * 2).toStringAsFixed(1)),
        'count': sorted.length,
        'latest_date': sorted.isEmpty ? null : _ymd(sorted.last.date),
      },
      'workouts': {
        'count': weekWorkouts.length,
        'days': weekWorkouts
            .map((w) => DateTime(w.date.year, w.date.month, w.date.day))
            .toSet()
            .length,
        'minutes': weekWorkouts.fold<int>(
            0, (sum, w) => sum + ((w.durationSec ?? 0) / 60).round()),
      },
      'water_cups_today': cups,
      'calories_today': calories.round(),
    });
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
