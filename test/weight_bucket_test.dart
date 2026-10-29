import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/weight_bucket.dart';

BodyMetricEntity _m(DateTime date, double kg) =>
    BodyMetricEntity(id: date.millisecondsSinceEpoch, date: date, weightKg: kg);

void main() {
  final now = DateTime(2025, 3, 5); // 周三

  group('bucketWeightSeries', () {
    test('空数据 → 空序列（不补 0 桶）', () {
      expect(
        bucketWeightSeries(const [], range: WeightRange.month, now: now),
        isEmpty,
      );
    });

    test('单条 → 一个桶，平均 == 最低 == 该值', () {
      final b = bucketWeightSeries(
        [_m(DateTime(2025, 3, 3), 70)],
        range: WeightRange.month,
        now: now,
      );
      expect(b, hasLength(1));
      expect(b.single.avgKg, 70);
      expect(b.single.minKg, 70);
      expect(b.single.count, 1);
    });

    test('同周多条 → 平均与最低分别算对', () {
      final b = bucketWeightSeries(
        [
          _m(DateTime(2025, 3, 3), 70),
          _m(DateTime(2025, 3, 4), 68),
          _m(DateTime(2025, 3, 5), 71),
        ],
        range: WeightRange.week,
        now: now,
      );
      expect(b, hasLength(1));
      expect(b.single.avgKg, closeTo((70 + 68 + 71) / 3, 1e-9));
      expect(b.single.minKg, 68);
      expect(b.single.count, 3);
    });

    test('跨周分组边界：周一起止（周一那条属于新桶）', () {
      // 2025-03-03 是周一；03-02 是周日
      final b = bucketWeightSeries(
        [
          _m(DateTime(2025, 3, 2), 72), // 上一周（周日）
          _m(DateTime(2025, 3, 3), 70), // 这一周（周一）
        ],
        range: WeightRange.all,
        now: now,
      );
      expect(b.length, 2, reason: '周日与周一必须落在不同桶');
      expect(b.first.avgKg, 72);
      expect(b.last.avgKg, 70);
    });

    test('「全部」档：跨度长时自动放大桶宽（避免一根柱代表一个月）', () {
      final b = bucketWeightSeries(
        [
          _m(DateTime(2024, 1, 1), 80),
          _m(DateTime(2024, 12, 1), 70),
          _m(DateTime(2025, 3, 1), 68),
        ],
        range: WeightRange.all,
        now: now,
      );
      expect(b.length, lessThanOrEqualTo(4), reason: '一年多跨度应该聚成少量柱，而不是一天一根');
    });

    test('体重 <= 0 的脏记录不参与（否则把桶平均值拉垮）', () {
      final b = bucketWeightSeries(
        [
          _m(DateTime(2025, 3, 3), 70),
          _m(DateTime(2025, 3, 4), 0),
        ],
        range: WeightRange.week,
        now: now,
      );
      expect(b.single.count, 1);
      expect(b.single.avgKg, 70);
    });

    test('超出时间范围的记录被裁掉', () {
      final b = bucketWeightSeries(
        [
          _m(DateTime(2025, 1, 1), 90), // 62 天前，不在周档范围
          _m(DateTime(2025, 3, 4), 70),
        ],
        range: WeightRange.week,
        now: now,
      );
      expect(b, hasLength(1));
      expect(b.single.avgKg, 70);
    });
  });

  group('predictWeightTrend', () {
    test('少于 3 条不预测', () {
      expect(
        predictWeightTrend([_m(DateTime(2025, 3, 3), 70)]),
        isNull,
      );
    });

    test('目标为 null → 只有斜率，没有达标天数（不画 0kg 基准的等价物）', () {
      final p = predictWeightTrend([
        _m(DateTime(2025, 3, 1), 72),
        _m(DateTime(2025, 3, 2), 71.5),
        _m(DateTime(2025, 3, 3), 71),
      ]);
      expect(p, isNotNull);
      expect(p!.daysToTarget, isNull);
      expect(p.slopePerWeek, lessThan(0), reason: '体重在降 → 斜率为负');
    });

    test('有目标且能收敛 → 给出达标天数与方向', () {
      final p = predictWeightTrend(
        [
          _m(DateTime(2025, 3, 1), 72),
          _m(DateTime(2025, 3, 2), 71.5),
          _m(DateTime(2025, 3, 3), 71),
        ],
        targetKg: 68,
      );
      expect(p!.daysToTarget, isNotNull);
      expect(p.daysToTarget, greaterThan(0));
      expect(p.direction, '下降');
    });

    test('体重完全不变化 → 不预测（斜率为 0 没有预测意义）', () {
      final p = predictWeightTrend(
        [
          _m(DateTime(2025, 3, 1), 70),
          _m(DateTime(2025, 3, 2), 70),
          _m(DateTime(2025, 3, 3), 70),
        ],
        targetKg: 65,
      );
      expect(p!.daysToTarget, isNull);
    });
  });

  group('weekChangeKg（沿用本页既有口径：7 天前最后一条）', () {
    test('有 7 天前的记录 → 给出差值', () {
      final c = weekChangeKg(
        [
          _m(DateTime(2025, 2, 20), 73),
          _m(DateTime(2025, 3, 4), 71),
        ],
        now: now,
      );
      expect(c, closeTo(-2, 1e-9));
    });

    test('没有 7 天前的记录 → null（不编一个 0）', () {
      expect(
        weekChangeKg([_m(DateTime(2025, 3, 4), 71)], now: now),
        isNull,
      );
    });
  });
}
