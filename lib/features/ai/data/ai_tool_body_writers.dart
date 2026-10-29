import 'dart:convert';

import 'package:fittrack/features/ai/data/ai_tool_handler.dart';
import 'package:fittrack/features/ai/domain/ai_tool.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

/// 身体记录类工具：query_measurements / update_measurement / delete_measurement
///
/// 数据走 `repos.body`（body_metrics 表：体重 + 腰/臀/胸围）。
/// `update_measurement` 的 preview 必须列**改前 → 改后**——
/// 不让用户点确认时还猜不出到底会改成什么。
class AiToolBodyWriters extends AiToolHandler {
  const AiToolBodyWriters(super.repos);

  @override
  Set<String> get toolNames => const {
        AiToolSpecs.queryMeasurements,
        AiToolSpecs.updateMeasurement,
        AiToolSpecs.deleteMeasurement,
      };

  @override
  Future<AiToolPreview> preview(AiToolCall call) async {
    switch (call.name) {
      case AiToolSpecs.queryMeasurements:
        return AiToolPreview(
          call: call,
          label: '查询身体记录',
          detail: '查看最近的围度/体脂记录与各部位最新值',
          needsConfirm: false,
        );

      case AiToolSpecs.updateMeasurement:
        final target = await _locate(call.arguments);
        final patch = _patch(call.arguments);
        return AiToolPreview(
          call: call,
          label: '修改身体记录',
          detail:
              '${_describe(target)}：${_before(target)} → ${_after(target, patch)}',
          needsConfirm: true,
        );

      case AiToolSpecs.deleteMeasurement:
        final target = await _locate(call.arguments);
        return AiToolPreview(
          call: call,
          label: '删除身体记录',
          detail: '${_describe(target)}：${_before(target)}（删除后无法恢复）',
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
      case AiToolSpecs.queryMeasurements:
        return _query(call.arguments);
      case AiToolSpecs.updateMeasurement:
        return _update(call.arguments);
      case AiToolSpecs.deleteMeasurement:
        return _delete(call.arguments);
      default:
        unsupported(call);
    }
  }

  /// 查询条数（1~30，默认 10；越界按默认处理，不抛）
  int _limit(Map<String, dynamic> args) {
    final v = AiToolArgs.lenientIntOf(args['limit']);
    if (v == null || v < 1 || v > 30) return 10;
    return v;
  }

  // ───────────── query ─────────────

  Future<String> _query(Map<String, dynamic> args) async {
    final limit = _limit(args);
    final logs = await repos.body.getRecent(limit: limit);

    final items = logs
        .map((l) => {
              'id': l.id,
              'date': _day(l.date),
              'weight_kg': l.weightKg,
              'waist_cm': l.waistCm,
              'hip_cm': l.hipCm,
              'chest_cm': l.chestCm,
              'note': l.note,
            })
        .toList();

    // 各部位最新值（null = 该部位从未记录过，**不写 0** —— 0 代表"真的是 0"）
    final pickers = <String, double? Function(BodyMetricEntity)>{
      'weight_kg': (e) => e.weightKg,
      'waist_cm': (e) => e.waistCm,
      'hip_cm': (e) => e.hipCm,
      'chest_cm': (e) => e.chestCm,
    };
    final latest = <String, dynamic>{};
    pickers.forEach((key, pick) {
      for (final l in logs) {
        final v = pick(l);
        if (v != null) {
          latest[key] = v;
          return;
        }
      }
      latest[key] = null;
    });

    return jsonEncode({
      'ok': true,
      'count': items.length,
      'items': items,
      'latest': latest,
    });
  }

  // ───────────── update ─────────────

  Future<String> _update(Map<String, dynamic> args) async {
    final target = await _locate(args);
    final patch = _patch(args);
    final newTarget = _applyPatch(target, patch);

    await repos.body.update(
      id: newTarget.id,
      date: newTarget.date,
      weightKg: newTarget.weightKg,
      waistCm: newTarget.waistCm,
      hipCm: newTarget.hipCm,
      chestCm: newTarget.chestCm,
      note: newTarget.note,
    );
    return jsonEncode({
      'ok': true,
      'id': newTarget.id,
      'date': _day(newTarget.date),
      'weight_kg': newTarget.weightKg,
      'waist_cm': newTarget.waistCm,
      'hip_cm': newTarget.hipCm,
      'chest_cm': newTarget.chestCm,
    });
  }

  // ───────────── delete ─────────────

  Future<String> _delete(Map<String, dynamic> args) async {
    final target = await _locate(args);
    await repos.body.delete(target.id);
    return jsonEncode({
      'ok': true,
      'deleted_id': target.id,
      'date': _day(target.date),
    });
  }

  // ───────────── 定位与取值 ─────────────

  /// 定位目标记录：优先 id；否则 日期 + 部位（在该日期有该部位数值的记录里找最新）
  Future<BodyMetricEntity> _locate(Map<String, dynamic> args) async {
    final id = AiToolArgs.optionalMeasurementId(args);
    if (id != null) {
      final all = await repos.body.getAll();
      for (final row in all) {
        if (row.id == id) return row;
      }
      throw AiToolException('找不到 id 为 $id 的身体记录');
    }

    final date = AiToolArgs.optionalMeasurementDate(args);
    final part = AiToolArgs.measurementPart(args);
    if (date == null) {
      throw const AiToolException('定位记录需要 id，或 日期 + 部位（如 2025-03-04 + 腰围）');
    }
    final all = await repos.body.getAll(from: date, to: date);
    final sameDay = all.where((r) => _day(r.date) == _day(date)).toList();
    for (final row in sameDay) {
      final v = _pick(row, part);
      if (v != null) return row;
    }
    throw AiToolException('$_day(date) 没有「${_partLabel(part)}」的记录，先确认日期或改用 id');
  }

  /// 要改的数值（null = 不改该项）；`value`/`note` 都没给则视为空操作
  ({double? weight, double? waist, double? hip, double? chest, String? note})
      _patch(Map<String, dynamic> args) {
    final part = args['part'];
    final rawValue = AiToolArgs.optionalDouble(args, 'value');
    final note = args['note'] is String ? args['note'] as String : null;
    if (rawValue == null && note == null) {
      throw const AiToolException('至少要给一个新数值（value）或备注（note）');
    }
    return (
      weight: part == 'weight' ? rawValue : null,
      waist: part == 'waist' ? rawValue : null,
      hip: part == 'hip' ? rawValue : null,
      chest: part == 'chest' ? rawValue : null,
      note: note,
    );
  }

  BodyMetricEntity _applyPatch(
    BodyMetricEntity target,
    ({
      double? weight,
      double? waist,
      double? hip,
      double? chest,
      String? note
    }) patch,
  ) {
    return BodyMetricEntity(
      id: target.id,
      date: target.date,
      weightKg: patch.weight ?? target.weightKg,
      waistCm: patch.waist ?? target.waistCm,
      hipCm: patch.hip ?? target.hipCm,
      chestCm: patch.chest ?? target.chestCm,
      note: patch.note ?? target.note,
    );
  }

  // ───────────── 文案辅助 ─────────────

  String _describe(BodyMetricEntity t) => '${_day(t.date)} 的身体记录 #${t.id}';

  String _before(BodyMetricEntity t) => _values(t);

  String _after(
    BodyMetricEntity t,
    ({
      double? weight,
      double? waist,
      double? hip,
      double? chest,
      String? note
    }) patch,
  ) =>
      _values(_applyPatch(t, patch));

  String _values(BodyMetricEntity t) {
    final parts = <String>['体重 ${t.weightKg}kg'];
    if (t.waistCm != null) parts.add('腰 ${t.waistCm}cm');
    if (t.hipCm != null) parts.add('臀 ${t.hipCm}cm');
    if (t.chestCm != null) parts.add('胸 ${t.chestCm}cm');
    return parts.join(' / ');
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  double? _pick(BodyMetricEntity r, String part) => switch (part) {
        'weight' => r.weightKg,
        'waist' => r.waistCm,
        'hip' => r.hipCm,
        'chest' => r.chestCm,
        _ => null,
      };

  String _partLabel(String part) => switch (part) {
        'weight' => '体重',
        'waist' => '腰围',
        'hip' => '臀围',
        'chest' => '胸围',
        _ => part,
      };
}
