import '../entities/body_metric_entity.dart';

abstract class BodyMetricRepository {
  Future<List<BodyMetricEntity>> getAll({DateTime? from, DateTime? to});
  Future<BodyMetricEntity?> getLatest();
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
