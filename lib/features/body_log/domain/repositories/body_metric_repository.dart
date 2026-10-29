import '../entities/body_metric_entity.dart';

abstract class BodyMetricRepository {
  Future<List<BodyMetricEntity>> getAll({DateTime? from, DateTime? to});
  Future<BodyMetricEntity?> getLatest();

  /// 最近 [limit] 条（按日期倒序），供 AI 查询身体记录列表
  Future<List<BodyMetricEntity>> getRecent({int limit = 10});
  Future<BodyMetricEntity> create({
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  });
  Future<void> update({
    required int id,
    required DateTime date,
    required double weightKg,
    double? waistCm,
    double? hipCm,
    double? chestCm,
    String? note,
  });
  Future<void> delete(int id);
}
