import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';

/// 管理类写操作：manage_goal / delete_records（删除为危险操作）
class AiToolAdminWriters extends AiToolHandler {
  const AiToolAdminWriters(super.repos);

  @override
  Set<String> get toolNames =>
      const {AiToolSpecs.manageGoal, AiToolSpecs.deleteRecords};

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.manageGoal:
        final cmd = _command(call.arguments);
        final String label;
        final String detail;
        if (cmd.isCreate) {
          label = '新建目标';
          detail = cmd.createDetail;
        } else if (cmd.action == AiGoalActions.complete) {
          label = '完成目标';
          detail = '完成目标 #${cmd.goalId}';
        } else {
          label = '删除目标';
          detail = '删除目标 #${cmd.goalId}';
        }
        return AiToolPreview(
          call: call,
          label: label,
          detail: detail,
          needsConfirm: true,
          // 删除目标是危险操作：确认卡必须走警示样式；create / complete 保持普通样式
          isDestructive: cmd.isDestructive,
        );

      case AiToolSpecs.deleteRecords:
        final args = call.arguments;
        final type = AiToolArgs.recordType(args);
        final date = AiToolArgs.date(args);
        // 先查库统计条数：没有记录就不打扰用户（也避免模型声称"删掉了"）
        final summary = await _summarize(type, date);
        if (summary.isEmpty) throw AiRecordTypes.emptyOf(type);
        return AiToolPreview(
          call: call,
          label: '删除${AiRecordTypes.labelOf(type)}记录',
          detail: summary.detail,
          needsConfirm: true,
          isDestructive: true,
        );

      default:
        unsupported(call);
    }
  }

  @override
  Future<String> execute(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.manageGoal:
        return _manageGoal(_command(call.arguments));
      case AiToolSpecs.deleteRecords:
        return _deleteRecords(call.arguments);
      default:
        unsupported(call);
    }
  }

  // ───────────── manage_goal ─────────────

  AiGoalCommand _command(Map<String, dynamic> args) {
    final action = AiToolArgs.goalAction(args);
    if (action != AiGoalActions.create) {
      return AiGoalCommand(action: action, goalId: AiToolArgs.goalId(args));
    }
    return AiGoalCommand(
      action: action,
      type: AiToolArgs.goalType(args),
      targetValue: AiToolArgs.goalTargetValue(args),
      category: AiToolArgs.goalCategory(args),
      endDate: AiToolArgs.goalEndDate(args),
    );
  }

  Future<String> _manageGoal(AiGoalCommand cmd) async {
    switch (cmd.action) {
      case AiGoalActions.create:
        final goal = await repos.goal.create(
          type: cmd.type!,
          category: cmd.category,
          targetValue: cmd.targetValue!,
          startDate: DateTime.now(),
          endDate: cmd.endDate,
        );
        return jsonEncode({
          'ok': true,
          'action': cmd.action,
          'goal': {
            'id': goal.id,
            'type': goal.type,
            'target_value': goal.targetValue,
            'unit': cmd.type == 'weight' ? '斤' : (cmd.type == 'frequency' ? '次' : ''),
          },
        });

      case AiGoalActions.complete:
        final id = cmd.goalId!;
        await _requireGoal(id);
        await repos.goal.complete(id);
        return jsonEncode({'ok': true, 'action': cmd.action, 'goal_id': id});

      default:
        final id = cmd.goalId!;
        await _requireGoal(id);
        await repos.goal.delete(id);
        return jsonEncode({'ok': true, 'action': cmd.action, 'goal_id': id});
    }
  }

  /// 目标不存在时明确报错，避免"删了个空气"还返回成功
  Future<void> _requireGoal(int id) async {
    final goal = await repos.goal.getById(id);
    if (goal == null) throw AiToolException('找不到目标 #$id');
  }

  // ───────────── delete_records ─────────────

  Future<String> _deleteRecords(Map<String, dynamic> args) async {
    final type = AiToolArgs.recordType(args);
    final date = AiToolArgs.date(args);
    final summary = await _summarize(type, date);
    if (summary.isEmpty) throw AiRecordTypes.emptyOf(type);

    switch (type) {
      case AiRecordTypes.weight:
        for (final id in summary.ids) {
          await repos.body.delete(id);
        }
      case AiRecordTypes.food:
        for (final id in summary.ids) {
          await repos.diet.deleteLog(id);
        }
      case AiRecordTypes.workout:
        for (final id in summary.ids) {
          await repos.workout.delete(id);
        }
      default:
        // 饮水按天汇总存储，只能清零当天
        await repos.water.setTodayCups(0);
    }

    return jsonEncode({
      'ok': true,
      'type': type,
      'date': AiToolFormat.ymd(date),
      'deleted': summary.count,
      if (type == AiRecordTypes.food)
        'kcal_deleted': summary.kcal.round(),
    });
  }

  /// 统计某天某类型的记录（preview 与 execute 共用，execute 会重新统计一次）
  Future<_DeletionSummary> _summarize(String type, DateTime date) async {
    switch (type) {
      case AiRecordTypes.weight:
        final rows = await repos.body.getAll(from: date, to: date);
        return _DeletionSummary(
          type: type,
          date: date,
          ids: rows.map((r) => r.id).toList(),
        );

      case AiRecordTypes.food:
        final logs = await repos.diet.getLogsByDate(date);
        return _DeletionSummary(
          type: type,
          date: date,
          ids: logs.map((l) => l.id).toList(),
          kcal: logs.fold<double>(0, (sum, l) => sum + l.totalCalories),
        );

      case AiRecordTypes.workout:
        final rows = await repos.workout.getAll(from: date, to: date);
        return _DeletionSummary(
          type: type,
          date: date,
          ids: rows.map((r) => r.id).toList(),
        );

      default:
        // 饮水只有"今天的杯数"这一个可控入口，历史日期不可删（更安全：直接拦掉）
        final today = AiToolFormat.dayStart(DateTime.now());
        if (AiToolFormat.dayStart(date) != today) {
          throw const AiToolException('饮水只能删除今天的记录');
        }
        final cups = await repos.water.getTodayCups();
        return _DeletionSummary(
          type: type,
          date: date,
          ids: const [],
          cups: cups,
        );
    }
  }
}

/// 一次删除操作的统计结果（条数 / 关联 id / 热量）
class _DeletionSummary {
  final String type;
  final DateTime date;
  final List<int> ids;

  /// 饮食记录的总热量（其他类型为 0）
  final double kcal;

  /// 饮水杯数（非饮水类型为 0）
  final int cups;

  const _DeletionSummary({
    required this.type,
    required this.date,
    required this.ids,
    this.kcal = 0,
    this.cups = 0,
  });

  /// 饮水按"有没有喝过水"算 1 条，其余按记录条数
  int get count => type == AiRecordTypes.water ? (cups > 0 ? 1 : 0) : ids.length;

  bool get isEmpty => count == 0;

  /// 如「删除今天的 3 条饮食记录，共约 850 千卡」
  String get detail {
    final label = AiRecordTypes.labelOf(type);
    final when = AiToolArgs.dateLabel(date);
    final head = when == '今天' || when == '昨天' ? '删除$when的' : '删除 $when 的';
    if (type == AiRecordTypes.water) {
      return '$head饮水记录（$cups 杯）';
    }
    final tail = type == AiRecordTypes.food ? '，共约 ${kcal.round()} 千卡' : '';
    return '$head $count 条$label记录$tail';
  }
}
